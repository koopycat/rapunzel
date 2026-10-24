#!/usr/bin/env bash
set -Eeuo pipefail
# Fast host tests. Docker must never run during configuration inspection.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/rapunzel-control-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
mkdir "$test_dir/bin" "$test_dir/project"
cat >"$test_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected Docker call\n' >&2
exit 99
EOF
chmod +x "$test_dir/bin/docker"

config() {
    env -u RAPUNZEL_HARNESS -u RAPUNZEL_NETWORK -u RAPUNZEL_API_KEY_VARIABLE -u RAPUNZEL_API_BASE_URL \
        -u RAPUNZEL_BASE_URL -u ANTHROPIC_API_KEY -u OPENAI_API_KEY \
        -u RAPUNZEL_EGRESS_ALLOW -u RAPUNZEL_EGRESS_ALLOW_PRIVATE -u RAPUNZEL_EGRESS_LOGINS \
        -u RAPUNZEL_BASE_URL_VARIABLE -u RAPUNZEL_PIDS_LIMIT -u RAPUNZEL_MEMORY -u RAPUNZEL_WORKSPACE PATH="$test_dir/bin:$PATH" RAPUNZEL_ENV_FILE= "$@" \
        "$ROOT/rapunzel-ctl" config "$test_dir/project" --harness pi
}

output=$(config RAPUNZEL_EGRESS=allowlist OPENAI_API_KEY=secret-env \
    RAPUNZEL_EGRESS_ALLOW=docs.example.com RAPUNZEL_EGRESS_LOGINS=anthropic \
    RAPUNZEL_EGRESS_ALLOW_PRIVATE=router.example.lan)
jq -e '.policy.baseline | index("api.openai.com") != null' <<<"$output" >/dev/null
jq -e '.policy.private == ["router.example.lan"] and (.credentials | any(.name == "OPENAI_API_KEY" and .source == "environment"))' <<<"$output" >/dev/null
[[ "$output" != *secret-env* ]]
[[ ! -e "$test_dir/project/.git" ]]

cat >"$test_dir/provider.env" <<'EOF'
OPENAI_API_KEY=secret-file
RAPUNZEL_API_BASE_URL=https://router.example.com/super-secret-path
RAPUNZEL_API_KEY_VARIABLE=ROUTER_KEY
ROUTER_KEY=secret-router
EOF
chmod 600 "$test_dir/provider.env"
output=$(config RAPUNZEL_EGRESS=allowlist RAPUNZEL_ENV_FILE="$test_dir/provider.env" OPENAI_API_KEY=secret-override)
jq -e '.policy.baseline | index("router.example.com") != null' <<<"$output" >/dev/null
jq -e '.credentials | any(.name == "OPENAI_API_KEY" and .source == "environment")' <<<"$output" >/dev/null
[[ "$output" != *secret-file* && "$output" != *secret-override* && "$output" != *secret-router* && "$output" != *super-secret-path* ]]
output=$(config RAPUNZEL_EGRESS=strict OPENAI_API_KEY=secret-env)
jq -e '.providerKeysEnterAgent == false' <<<"$output" >/dev/null

# Inspection does not create a filtered secret file; even an unavailable TMPDIR
# is fine. Invalid/unsupported host policy must still be rejected without Docker.
output=$(config RAPUNZEL_EGRESS=allowlist RAPUNZEL_ENV_FILE="$test_dir/provider.env" TMPDIR="$test_dir/missing")
[[ "$output" != *secret-file* ]]
if config RAPUNZEL_EGRESS=allowlist RAPUNZEL_EGRESS_ALLOW='example.com; echo injected' >/dev/null 2>&1; then exit 1; fi
for url in 'https://user:secret@example.com/private' 'https://example.com/path?token=secret' 'not-a-url'; do
    if config RAPUNZEL_EGRESS=allowlist RAPUNZEL_API_BASE_URL="$url" >"$test_dir/invalid-url" 2>&1; then exit 1; fi
    [[ "$(<"$test_dir/invalid-url")" != *secret* ]]
done

# Resource limits: a process limit by default, memory only when set, and
# invalid values refused before Docker.
output=$(config)
jq -e '.limits == {pids: 4096, memory: null}' <<<"$output" >/dev/null
output=$(config RAPUNZEL_PIDS_LIMIT=8192 RAPUNZEL_MEMORY=8g)
jq -e '.limits == {pids: 8192, memory: 8589934592}' <<<"$output" >/dev/null
for setting in RAPUNZEL_PIDS_LIMIT=unlimited RAPUNZEL_PIDS_LIMIT=10 RAPUNZEL_MEMORY=lots RAPUNZEL_MEMORY=1m; do
    if config "$setting" >/dev/null 2>&1; then exit 1; fi
done

# Workspace mode: only mount or clone, and clone needs a repository with a
# commit, checked before Docker. The report names the workspace volume.
jq -e '.workspace == "mount" and .workspaceVolume == null' <<<"$(config)" >/dev/null
if config RAPUNZEL_WORKSPACE=copy >/dev/null 2>&1; then exit 1; fi
if config RAPUNZEL_WORKSPACE=clone >/dev/null 2>&1; then exit 1; fi
git init --quiet "$test_dir/repo"
if PATH="$test_dir/bin:$PATH" RAPUNZEL_ENV_FILE='' RAPUNZEL_WORKSPACE=clone \
    "$ROOT/rapunzel-ctl" config "$test_dir/repo" >/dev/null 2>&1; then exit 1; fi
git -C "$test_dir/repo" -c user.name=test -c user.email=test@example.invalid commit --quiet --allow-empty -m base
output=$(PATH="$test_dir/bin:$PATH" RAPUNZEL_ENV_FILE='' RAPUNZEL_WORKSPACE=clone \
    "$ROOT/rapunzel-ctl" config "$test_dir/repo" --harness pi)
jq -e '.workspace == "clone" and (.workspaceVolume | test("^rapunzel-pi-[0-9a-f]{12}-workspace$"))' <<<"$output" >/dev/null

# The control registry itself must not be agent-writable or follow a final
# symlink. These tests do not create or inspect any Docker resource.
# shellcheck source=lib/runs.sh
source "$ROOT/lib/runs.sh"
mkdir -m 755 "$test_dir/unsafe-runs"
if (RAPUNZEL_RUNS_DIR="$test_dir/unsafe-runs" runs_root) >/dev/null 2>&1; then exit 1; fi
mkdir -m 700 "$test_dir/safe-runs"
ln -s "$test_dir/safe-runs" "$test_dir/linked-runs"
if (RAPUNZEL_RUNS_DIR="$test_dir/linked-runs" runs_root) >/dev/null 2>&1; then exit 1; fi
RAPUNZEL_RUNS_DIR="$test_dir/safe-runs" runs_root

# Host controls fail before mutation for wildcards and injection-shaped targets.
# shellcheck source=lib/egress.sh
source "$ROOT/lib/egress.sh"
long_label=$(printf '%064d' 0)
long_name="${long_label:0:63}.${long_label:0:63}.${long_label:0:63}.${long_label:0:63}.com"
for host in '1.1.1.1' 'https://example.com' 'example.com:443' 'example.com/path' $'example.com\nother.com' '-bad.com' 'bad-.com' "$long_label.com" "$long_name"; do
    if (egress_allow_host "$host") >/dev/null 2>&1; then printf 'FAIL: accepted %q\n' "$host" >&2; exit 1; fi
done
egress_allow_host "${long_label:0:63}.example.com"
if (egress_allow_host $'bad\033[2J.com') >"$test_dir/invalid-host" 2>&1; then exit 1; fi
[[ "$(<"$test_dir/invalid-host")" != *$'\033'* ]]
if (egress_allow_private_host '*.example.com') >/dev/null 2>&1; then exit 1; fi
EGRESS_HOSTS=(api.openai.com) EGRESS_PRIVATE_HOSTS=()
allowlist_configure "$test_dir"
grep -q 'sni_verification: true' "$test_dir/pipelock.yaml"
grep -q 'sni_require_tls: true' "$test_dir/pipelock.yaml"
grep -q '    max_requests_per_minute: 1000000' "$test_dir/pipelock.yaml"

# Strict gateway: an Anthropic API key authenticates with X-Api-Key, a
# subscription token with Authorization: Bearer; the key wins over the token,
# and no secret ever appears in the rendered Caddyfile.
gateway_render() {
    (
        GATEWAY_PROVIDERS="" GATEWAY_ANTHROPIC_AUTH=""
        GW_ANTHROPIC_API_KEY=$1 GW_ANTHROPIC_OAUTH=$2 GW_OPENAI_API_KEY="" GW_CUSTOM_URL="" \
            gateway_configure "$test_dir"
        printf '%s\n' "$GATEWAY_ANTHROPIC_AUTH"
    )
}
[[ "$(gateway_render secret-api-key '')" == api-key ]]
grep -q 'header_up X-Api-Key {env.GW_ANTHROPIC_API_KEY}' "$test_dir/Caddyfile"
grep -q 'header_up -Authorization' "$test_dir/Caddyfile"
[[ "$(gateway_render '' secret-oauth-token)" == oauth ]]
grep -q 'header_up Authorization "Bearer {env.GW_ANTHROPIC_OAUTH}"' "$test_dir/Caddyfile"
grep -q 'header_up -X-Api-Key' "$test_dir/Caddyfile"
grep -qx 'GW_ANTHROPIC_OAUTH=secret-oauth-token' "$test_dir/gateway.env"
[[ "$(gateway_render secret-api-key secret-oauth-token)" == api-key ]]
if grep -q GW_ANTHROPIC_OAUTH "$test_dir/Caddyfile"; then exit 1; fi
if grep -q 'secret-' "$test_dir/Caddyfile"; then exit 1; fi

# A block log is data: avoid headers, raw reasons/URLs and terminal control
# characters, and never present SNI violations as ordinary host approvals.
# shellcheck source=lib/control.sh
source "$ROOT/lib/control.sh"
docker() {
    printf '%s\n' '{"event":"blocked","method":"CONNECT","target":"evil\u001b[2J.com:443","scanner":"allowlist","reason":"SECRET","headers":{"authorization":"SECRET"}}'
    printf '%s\n' '{"event":"sni_mismatch","connect_host":"example.com","sni_host":"evil.com"}'
    printf '%s\n' '{"event":"blocked","method":"CONNECT","target":"example.com:443","scanner":"allowlist"}'
}
# shellcheck disable=SC2119 # Snapshot intentionally has no --follow argument.
output=$(control_events)
[[ "$output" != *SECRET* && "$output" != *$'\033'* ]]
jq -se 'length == 3 and (.[0].approvalCandidate == false) and (.[1].approvalCandidate == false) and .[2].approvalCandidate' <<<"$output" >/dev/null

# Event candidates use the grant grammar, and ports are bounded. Arbitrary JSON
# lines and malformed targets remain diagnostics rather than disappearing.
docker() {
    local target
    for target in '-bad.com:443' 'bad-.com:443' 'example.com:0' 'example.com:65536' 'EXAMPLE.COM:443' "$long_label.com:443"; do
        jq -nc --arg target "$target" '{event:"blocked",method:"CONNECT",scanner:"allowlist",target:$target}'
    done
    printf '%s\n' 'null' '[]' '42' '"text"' 'invalid json'
}
output=$(control_events)
jq -se 'length == 6 and ([.[] | select(.approvalCandidate)] | length == 1) and .[4].host == "example.com"' <<<"$output" >/dev/null
docker() { printf 'sensitive Docker error\n' >&2; return 7; }
if control_events >"$test_dir/events" 2>"$test_dir/log-error"; then exit 1; fi
grep -q 'could not read block history' "$test_dir/log-error"
[[ "$(<"$test_dir/log-error")" != *sensitive* ]]

# Group by grant scope (host), not port. Counts are events in this window, not
# application requests. Current coverage never implies a successful retry.
RUN_ID=12345678aaaaaaaaaaaaaaaa
RUN_DIR="$test_dir/run"
mkdir "$RUN_DIR"
printf '%s\n' '{"policy":{"baseline":["*.example.org","router.lan"],"grants":["example.com"],"private":["router.lan"]}}' >"$RUN_DIR/run.json"
docker() {
    printf '%s\n' \
        '{"event":"blocked","method":"CONNECT","scanner":"allowlist","target":"example.com:443","time":"2026-10-17T01:00:00Z"}' \
        '{"event":"blocked","method":"CONNECT","scanner":"allowlist","target":"example.com:8443","time":"2026-10-17T02:00:00Z"}' \
        '{"event":"blocked","method":"CONNECT","scanner":"allowlist","target":"docs.example.org:443"}' \
        '{"event":"blocked","method":"CONNECT","scanner":"ssrf","target":"router.lan:443"}' \
        '{"event":"blocked","method":"CONNECT","scanner":"allowlist","target":"mixed.test:443"}' \
        '{"event":"sni_mismatch","connect_host":"mixed.test"}' \
        '{"event":"blocked","method":"CONNECT","scanner":"allowlist","target":"new.test:443"}'
}
output=$(control_pending)
jq -e '.schemaVersion == 1 and .historyLimit == 2000 and
    any(.destinations[]; .host == "example.com" and .ports == [443,8443] and .events == 2 and .coverage == "runtime" and (.approvalCandidate | not)) and
    any(.destinations[]; .host == "docs.example.org" and .coverage == "startup") and
    any(.destinations[]; .host == "router.lan" and .privateTrusted and (.approvalCandidate | not)) and
    any(.destinations[]; .host == "mixed.test" and (.approvalCandidate | not)) and
    any(.destinations[]; .host == "new.test" and .approvalCandidate)' <<<"$output" >/dev/null
touch "$RUN_DIR/uncertain"
control_pending | jq -e '(.policyKnown | not) and all(.destinations[]; .coverage == "unknown" and (.approvalCandidate | not))' >/dev/null
rm "$RUN_DIR/uncertain"
docker() { :; }
control_pending | jq -e '.destinations == []' >/dev/null

# A prefix is resolved once, including stale/foreign collisions; no newest-run
# guessing. A full ID still selects the intended record when prefixes collide.
export RAPUNZEL_RUNS_DIR="$test_dir/safe-runs"
mkdir "$RAPUNZEL_RUNS_DIR/12345678aaaaaaaaaaaaaaaa"
run_resolve 12345678
[[ "$RUN_ID" == 12345678aaaaaaaaaaaaaaaa ]]
mkdir "$RAPUNZEL_RUNS_DIR/12345678bbbbbbbbbbbbbbbb"
if run_resolve 12345678 2>/dev/null; then exit 1; fi
run_resolve 12345678aaaaaaaaaaaaaaaa
if run_resolve 1234567 2>/dev/null; then exit 1; fi
if run_resolve '../other' 2>/dev/null; then exit 1; fi
if run_resolve ffffffff >"$test_dir/selector" 2>&1; then exit 1; fi
grep -q 'may have ended' "$test_dir/selector"

# Discovery must use this registry/daemon and verify live labels. Arbitrary
# labeled containers, stale metadata and foreign records are not listed.
for suffix in aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb; do
    id="12345678$suffix"
    jq -n --arg id "$id" '{run:$id,agent:("rapunzel-agent-"+$id),daemon:"this-daemon",status:"running",project:"/project",harness:"pi",egress:"allowlist"}' \
        >"$RAPUNZEL_RUNS_DIR/$id/run.json"
done
docker() {
    if [[ "$1" == info ]]; then printf 'this-daemon\n'
    elif [[ "${*: -1}" == rapunzel-agent-12345678aaaaaaaaaaaaaaaa ]]; then printf '12345678aaaaaaaaaaaaaaaa true\n'
    else printf '12345678bbbbbbbbbbbbbbbb false\n'; fi
}
run_list | jq -e 'length == 1 and .[0].run == "12345678aaaaaaaaaaaaaaaa"' >/dev/null
jq '.daemon="other-daemon"' "$RAPUNZEL_RUNS_DIR/12345678aaaaaaaaaaaaaaaa/run.json" >"$test_dir/foreign"
mv "$test_dir/foreign" "$RAPUNZEL_RUNS_DIR/12345678aaaaaaaaaaaaaaaa/run.json"
run_list | jq -e 'length == 0' >/dev/null
if run_select 12345678aaaaaaaaaaaaaaaa >/dev/null 2>&1; then exit 1; fi

# No raw Unicode/bidi or terminal controls escape text rendering, including
# paths on a line of their own. --json stays explicit even on a terminal.
SCRIPT_DIR=$ROOT CTL_FORMAT=text
# shellcheck source=lib/ctl-output.sh
source "$ROOT/lib/ctl-output.sh"
unicode=$(jq -nr '"\u202e\ud83d\udc08"')
output=$(jq -n --arg project $'path\033[2J\n'"$unicode" '[{run:"12345678aaaaaaaaaaaaaaaa",harness:"pi",egress:"allowlist",status:"running",project:$project}]' | ctl_render runs)
[[ "$output" != *$'\033'* && "$output" != *"$unicode"* && "$output" == *'\u001b'* && "$output" == *'\u202e\ud83d\udc08'* ]]
PATH="$test_dir/bin:$PATH" RAPUNZEL_ENV_FILE='' "$ROOT/rapunzel-ctl" --format=text config "$test_dir/project" >"$test_dir/text-config"
grep -q 'Project:' "$test_dir/text-config"
grep -q 'Limits: processes 4096, memory none' "$test_dir/text-config"
PATH="$test_dir/bin:$PATH" RAPUNZEL_ENV_FILE='' "$ROOT/rapunzel-ctl" --json config "$test_dir/project" | jq -e '.harness == "pi"' >/dev/null

# Evidence queries must not inherit the diagnostic --tail limit. Log-read
# failure cannot be confused with an empty/unsuccessful acknowledgement.
mkdir "$RUN_DIR/control.lock"
printf '2026-10-17T00:00:00.000000001Z\n' >"$RUN_DIR/control.lock/since"
docker() {
    [[ " $* " != *' --tail '* ]] || return 1
    printf '%s\n' '{"event":"config_reload","status":"success","config_hash":"expected"}'
}
control_wait_hash expected

# Shutdown wording must be based on inspect, never merely a best-effort stop.
docker() { if [[ "$1" == inspect ]]; then printf 'true\n'; else return 1; fi; }
output=$(control_stop_uncertain 2>&1)
[[ "$output" == *'could not be confirmed'* && "$output" != *'confirmed stopped'* ]]
docker() { if [[ "$1" == inspect ]]; then printf 'false\n'; fi; }
output=$(control_stop_uncertain 2>&1)
[[ "$output" == *'confirmed stopped'* ]]

# Strict gateway: built-in providers render from GATEWAY_BUILTINS, keys stay
# in the env-file, every route drops ?key=, and openrouter splits /v1/*.
gw_dir="$test_dir/gateway"
mkdir "$gw_dir"
GATEWAY_PROVIDERS=""
GW_GEMINI_API_KEY=gemini-secret GW_OPENROUTER_API_KEY=or-secret gateway_configure "$gw_dir"
[[ "$GATEWAY_PROVIDERS" == openrouter,google ]]
if grep -q secret "$gw_dir/Caddyfile"; then
    printf 'FAIL: a key reached the rendered Caddyfile\n' >&2
    exit 1
fi
grep -qx 'GW_GEMINI_API_KEY=gemini-secret' "$gw_dir/gateway.env"
grep -q 'header_up X-Goog-Api-Key {env.GW_GEMINI_API_KEY}' "$gw_dir/Caddyfile"
[[ $(grep -c 'uri query -key' "$gw_dir/Caddyfile") == 2 ]]
grep -q 'rewrite @v1 /api{uri}' "$gw_dir/Caddyfile"
grep -q 'rewrite \* /api/v1{uri}' "$gw_dir/Caddyfile"
[[ $(gateway_key_names | wc -l) -eq ${#GATEWAY_BUILTINS[@]} ]]

# Host-file mounts: .git is pinned onto its own path before the read-only
# parts, and symlinked git control paths stop the launch.
# shellcheck source=lib/host-files.sh
source "$ROOT/lib/host-files.sh"
hf_project="$test_dir/hf-project"
mkdir -p "$hf_project/.git/hooks"
: >"$hf_project/.git/config"
host_files_mounts "$hf_project"
[[ "${HOST_FILE_MOUNTS[1]}" == "type=bind,src=${hf_project}/.git,dst=/workspace/.git" ]]
[[ "${HOST_FILE_MOUNTS[3]}" == *"/.git/config,dst=/workspace/.git/config,readonly" ]]
rm -rf "$hf_project/.git/hooks"
ln -s "$test_dir" "$hf_project/.git/hooks"
if host_files_mounts "$hf_project" 2>/dev/null; then
    printf 'FAIL: a symlinked .git/hooks was accepted\n' >&2
    exit 1
fi

printf 'PASS: redacted config, validation, safe output, selectors, grouped history, log failures, shutdown wording, gateway routes, and host-file mounts (no Docker)\n'
