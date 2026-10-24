#!/usr/bin/env bash
set -Eeuo pipefail

# Checks RAPUNZEL_EGRESS=allowlist and RAPUNZEL_EGRESS=strict through the
# real launcher: rapunzel --exec runs lib/egress-probe.mjs inside the agent
# container. A canary on the host network must stay unreachable in both modes.
#
# allowlist needs internet access: it opens real tunnels to api.openai.com
#   (allowed through OPENAI_API_KEY) and chatgpt.com (allowed through
#   RAPUNZEL_EGRESS_LOGINS=openai-codex). Both are Cloudflare-hosted names,
#   which also exercises SNI-mismatch refusal.
# strict needs none: an echo server stands in for the provider.
#
# Usage: ./verify-egress.sh [allowlist|strict]...   (default: both)

SCRIPT_PATH=${BASH_SOURCE[0]}
# Follow symlinks so a link on PATH still finds lib/ in the checkout.
while [[ -L "$SCRIPT_PATH" ]]; do
    link=$(readlink -- "$SCRIPT_PATH")
    [[ "$link" == /* ]] || link="$(dirname -- "$SCRIPT_PATH")/$link"
    SCRIPT_PATH=$link
done
ROOT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/docker.sh
source "${ROOT_DIR}/lib/docker.sh"
IMAGE=${RAPUNZEL_IMAGE:-rapunzel}
# Checked in strict mode as well when these images have been built.
OPENCODE_IMAGE=${RAPUNZEL_OPENCODE_IMAGE:-rapunzel:opencode}
CLAUDE_IMAGE=${RAPUNZEL_CLAUDE_IMAGE:-rapunzel:claude}
VOLUME=${RAPUNZEL_VOLUME:-rapunzel-egress-check}
MODES=("$@")
[[ ${#MODES[@]} -gt 0 ]] || MODES=(allowlist strict)

require_docker verify-egress.sh
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
    printf 'Image %s is missing. Run docker build -t %s . first.\n' "$IMAGE" "$IMAGE" >&2
    exit 1
}

random_token() { od -An -N12 -tx1 /dev/urandom | tr -d ' \n'; }
upstream="rapunzel-egress-upstream-$$"
canary="rapunzel-egress-canary-$$"
canary_port=$((20000 + RANDOM % 20000))
# Inside the checkout, which Docker Desktop and Colima share by default; macOS
# $TMPDIR (/var/folders) is not shared with the Docker VM.
project=$(mktemp -d "${ROOT_DIR}/.rapunzel-verify.XXXXXX")
cleanup() {
    docker rm --force "$upstream" "$canary" >/dev/null 2>&1 || true
    rm -rf "$project"
}
trap cleanup EXIT

# A run may also sweep resources an earlier, killed run left behind, so only
# growth counts as a leak.
egress_resources() {
    {
        docker ps --all --quiet --filter label=rapunzel.egress=1
        docker network ls --quiet --filter label=rapunzel.egress=1
    } | wc -l | tr -d ' '
}
before=$(egress_resources)

# The canary listens on every host address, including a bridge's host side.
# Reaching it from the agent would mean the host is reachable.
docker run --detach --rm \
    --name "$canary" \
    --network host \
    --user 65534:65534 \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --entrypoint node \
    "$IMAGE" \
    -e 'require("node:http").createServer((req, res) => res.end("host reached"))
        .listen(Number(process.argv[1]), "0.0.0.0");' "$canary_port" >/dev/null

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Run the probe through rapunzel with the given environment assignments.
probe() {
    # An empty RAPUNZEL_ENV_FILE also keeps the launcher's default env file out.
    env -u RAPUNZEL_NETWORK -u RAPUNZEL_API_KEY_VARIABLE -u RAPUNZEL_HARNESS \
        -u ANTHROPIC_API_KEY -u OPENAI_API_KEY -u RAPUNZEL_API_BASE_URL -u RAPUNZEL_BASE_URL \
        -u RAPUNZEL_EGRESS_ALLOW -u RAPUNZEL_EGRESS_LOGINS -u RAPUNZEL_EGRESS_ALLOW_PRIVATE \
        -u RAPUNZEL_BASE_URL_VARIABLE \
        RAPUNZEL_ENV_FILE= \
        RAPUNZEL_IMAGE="$IMAGE" \
        RAPUNZEL_VOLUME="$VOLUME" \
        "$@" \
        "${ROOT_DIR}/rapunzel" --exec "$project" \
        node --input-type=module -e "$(<"${ROOT_DIR}/lib/egress-probe.mjs")" "${probe_args[@]}"
}

# Print the probe's checks and fail on any failed or missing one.
expect_checks() {
    local output=$1 minimum=$2
    grep '^CHECK ' <<<"$output" || true
    [[ "$(grep -c '^CHECK ' <<<"$output" || true)" -ge "$minimum" ]] || fail "probe did not report every check"
    if grep -q '^CHECK FAIL' <<<"$output"; then
        fail "egress checks failed"
    fi
}

section() { grep "^$2 " <<<"$1" || true; }

# Encrypted Client Hello (docs/egress.md D16): Pipelock up to the pinned 3.7.1
# reads only the plain server name, so an ECH hello with an allowed outer name
# passes, and Pipelock offers no setting to refuse it. If a release ever does,
# set this to true together with the pin and the config key; from then on a
# forwarded ECH hello fails the check.
PIPELOCK_REFUSES_ECH=false
expect_ech() {
    local line
    line=$(section "$1" ECH)
    if [[ -z "$line" ]]; then
        fail "probe did not report the ECH check"
    elif [[ "$PIPELOCK_REFUSES_ECH" == true ]]; then
        if [[ "$line" == "ECH refused"* ]]; then
            printf 'CHECK PASS Encrypted Client Hello refused (%s)\n' "${line#ECH }"
        else
            fail "the proxy forwarded an Encrypted Client Hello (${line#ECH })"
        fi
    elif [[ "$line" == "ECH forwarded"* ]]; then
        printf 'KNOWN GAP (risk 3): the proxy forwards an Encrypted Client Hello with an allowed outer name (%s)\n' "${line#ECH }"
    else
        fail "the proxy unexpectedly refused an Encrypted Client Hello (${line#ECH }); if the pinned Pipelock can now refuse ECH, set PIPELOCK_REFUSES_ECH=true"
    fi
}

check_allowlist() {
    printf '== allowlist with an API key (Pipelock CONNECT proxy, needs internet)\n'
    local key output env_line
    key="sk-dummy-$(random_token)"
    probe_args=(allowlist "$canary_port" api.openai.com)
    output=$(probe RAPUNZEL_EGRESS=allowlist OPENAI_API_KEY="$key")
    expect_checks "$output" 22
    expect_ech "$output"
    env_line=$(section "$output" ENV)
    # In this mode the agent holds the key by design.
    [[ "$env_line" == *"\"OPENAI_API_KEY\":\"${key}\""* ]] || fail "allowlist mode did not forward the provider key"
    [[ "$env_line" == *'"HTTPS_PROXY":"http://egress:8888"'* ]] || fail "HTTPS_PROXY is not set to the egress proxy"
    [[ "$env_line" != *'"HTTP_PROXY"'* ]] || fail "HTTP_PROXY is set; plain http:// should have no route"

    # A /login provider: the hosts come from RAPUNZEL_EGRESS_LOGINS alone.
    printf '== allowlist with a /login provider (openai-codex)\n'
    probe_args=(allowlist "$canary_port" chatgpt.com)
    output=$(probe RAPUNZEL_EGRESS=allowlist RAPUNZEL_EGRESS_LOGINS=openai-codex)
    expect_checks "$output" 22
    expect_ech "$output"

    check_private_host
}

# A self-signed HTTPS server published on the host, reached through a nip.io
# name that resolves to the default bridge's (private) gateway address.
check_private_host() {
    local port bridge_gateway name output
    docker run --detach --rm \
        --name "$upstream" \
        --publish 0:8443 \
        --user 65534:65534 \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --entrypoint bash \
        "$IMAGE" \
        -c 'cd /tmp && openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=rapunzel-test \
                -keyout key.pem -out cert.pem 2>/dev/null &&
            exec node -e "require(\"node:https\").createServer({ key: require(\"node:fs\").readFileSync(\"key.pem\"),
                cert: require(\"node:fs\").readFileSync(\"cert.pem\") }, (req, res) => res.end(\"private ok\")).listen(8443)"' \
        >/dev/null
    port=$(docker port "$upstream" 8443/tcp | head -n1 | sed 's/.*://')
    bridge_gateway=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
    name="${bridge_gateway}.nip.io"
    sleep 1

    printf '== allowlist with a private host in RAPUNZEL_EGRESS_ALLOW (%s)\n' "$name"
    probe_args=(allowlist "$canary_port" api.openai.com "${name}:${port}" refused)
    output=$(probe RAPUNZEL_EGRESS=allowlist OPENAI_API_KEY=sk-dummy RAPUNZEL_EGRESS_ALLOW="$name")
    expect_checks "$output" 23
    expect_ech "$output"

    printf '== allowlist with RAPUNZEL_EGRESS_ALLOW_PRIVATE (%s)\n' "$name"
    probe_args=(allowlist "$canary_port" api.openai.com "${name}:${port}" reachable)
    output=$(probe RAPUNZEL_EGRESS=allowlist OPENAI_API_KEY=sk-dummy RAPUNZEL_EGRESS_ALLOW_PRIVATE="$name")
    expect_checks "$output" 23
    expect_ech "$output"
    docker rm --force "$upstream" >/dev/null 2>&1 || true
}

# The echo server replies with the path and auth headers it received, plus a
# one-model list for clients that ask for /models. The gateway reaches it
# through a published port on the default bridge's host address, because each
# run's gateway sits on its own outbound network. Sets port and bridge_gateway.
start_echo() {
    docker run --detach --rm \
        --name "$upstream" \
        --publish 0:8080 \
        --user 65534:65534 \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --entrypoint node \
        "$IMAGE" \
        -e 'require("node:http").createServer((req, res) => {
            res.setHeader("content-type", "application/json");
            res.end(JSON.stringify({
                path: req.url,
                authorization: req.headers.authorization ?? null,
                xApiKey: req.headers["x-api-key"] ?? null,
                data: [{ id: "echo-model" }],
            }));
        }).listen(8080);' >/dev/null
    port=$(docker port "$upstream" 8080/tcp | head -n1 | sed 's/.*://')
    bridge_gateway=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
    [[ -n "$port" && -n "$bridge_gateway" ]] || {
        fail "echo upstream has no published port or bridge gateway"
        return 1
    }
}

check_strict() {
    printf '== strict (Caddy credential gateway, offline)\n'
    local secret anthropic_secret port bridge_gateway output env_line models_line echo_line value
    secret="pd-secret-$(random_token)"
    anthropic_secret="pd-secret-$(random_token)"

    start_echo || return
    probe_args=(strict "$bridge_gateway" "$port" "$canary_port")
    output=$(probe RAPUNZEL_EGRESS=strict \
        RAPUNZEL_PROVIDER=echo \
        RAPUNZEL_MODEL=echo-model \
        RAPUNZEL_API=openai-completions \
        RAPUNZEL_API_BASE_URL="http://${bridge_gateway}:${port}/v1" \
        RAPUNZEL_API_KEY_VARIABLE=EXAMPLE_API_KEY \
        EXAMPLE_API_KEY="$secret" \
        RAPUNZEL_BASE_URL_VARIABLE=EXAMPLE_BASE_URL \
        ANTHROPIC_API_KEY="$anthropic_secret")
    expect_checks "$output" 11

    env_line=$(section "$output" ENV)
    models_line=$(section "$output" MODELS)
    echo_line=$(section "$output" ECHO)
    [[ -n "$env_line" && -n "$models_line" && -n "$echo_line" ]] || fail "probe output is incomplete"
    for value in "$secret" "$anthropic_secret"; do
        [[ "$env_line" != *"$value"* ]] || fail "a real credential reached the agent environment"
        [[ "$models_line" != *"$value"* ]] || fail "a real credential reached models.json"
    done
    [[ "$models_line" == *'"baseUrl":"http://llm-proxy:8080/anthropic"'* ]] ||
        fail "models.json does not route anthropic through the gateway"
    [[ "$models_line" == *'"baseUrl":"http://llm-proxy:8080/custom"'* ]] ||
        fail "models.json does not route the custom provider through the gateway"
    # An extension provider reading its own variables gets the gateway route
    # and the placeholder key.
    [[ "$env_line" == *'"EXAMPLE_BASE_URL":"http://llm-proxy:8080/custom"'* ]] ||
        fail "RAPUNZEL_BASE_URL_VARIABLE does not point at the gateway"
    [[ "$env_line" == *'"EXAMPLE_API_KEY":"rapunzel-gateway"'* ]] ||
        fail "RAPUNZEL_API_KEY_VARIABLE does not hold the placeholder"
    [[ "$echo_line" == *"\"authorization\":\"Bearer ${secret}\""* ]] ||
        fail "the gateway did not replace the agent's Authorization header with the real key"
    [[ "$echo_line" == *'"xApiKey":null'* ]] || fail "the gateway forwarded the agent's x-api-key header"
    [[ "$echo_line" == *'"path":"/v1/echo?probe=1"'* ]] || fail "the gateway did not map /custom to the upstream path"
    [[ "$echo_line" != *attacker-key* ]] || fail "the agent's own credential reached the upstream"
    docker rm --force "$upstream" >/dev/null 2>&1 || true
}

# opencode in strict mode: its bootstrap must route the custom provider and the
# built-in anthropic provider through the gateway with the placeholder key,
# list the custom models through it, and keep every real key out of the
# sandbox.
check_strict_opencode() {
    printf '== strict with the opencode harness\n'
    local secret anthropic_secret port bridge_gateway output config_line env_line echo_line value
    secret="pd-secret-$(random_token)"
    anthropic_secret="pd-secret-$(random_token)"
    start_echo || return

    output=$(env -u RAPUNZEL_NETWORK -u RAPUNZEL_BASE_URL -u OPENAI_API_KEY \
        -u RAPUNZEL_EGRESS_ALLOW -u RAPUNZEL_EGRESS_LOGINS -u RAPUNZEL_EGRESS_ALLOW_PRIVATE \
        -u RAPUNZEL_BASE_URL_VARIABLE \
        RAPUNZEL_ENV_FILE= \
        RAPUNZEL_HARNESS=opencode \
        RAPUNZEL_IMAGE="$OPENCODE_IMAGE" \
        RAPUNZEL_VOLUME="${VOLUME}-opencode" \
        RAPUNZEL_EGRESS=strict \
        RAPUNZEL_PROVIDER=echo \
        RAPUNZEL_API_BASE_URL="http://${bridge_gateway}:${port}/v1" \
        RAPUNZEL_API_KEY_VARIABLE=EXAMPLE_API_KEY \
        EXAMPLE_API_KEY="$secret" \
        ANTHROPIC_API_KEY="$anthropic_secret" \
        "${ROOT_DIR}/rapunzel" --exec "$project" node -e '
            const fs = require("node:fs");
            const file = "/home/agent/.opencode-state/rapunzel/opencode.json";
            console.log("CONFIG " + fs.readFileSync(file, "utf8").replace(/\s+/g, ""));
            console.log("ENV " + JSON.stringify(process.env));
            // The custom route leads to the echo server, offline.
            fetch("http://llm-proxy:8080/custom/echo", { headers: { authorization: "Bearer attacker-key" } })
                .then((r) => r.text()).then((t) => console.log("ECHO " + t), (e) => console.log("ECHO error " + e));
        ' 2>&1)

    config_line=$(section "$output" CONFIG)
    env_line=$(section "$output" ENV)
    echo_line=$(section "$output" ECHO)
    [[ -n "$config_line" && -n "$env_line" && -n "$echo_line" ]] || {
        printf '%s\n' "$output" >&2
        fail "opencode probe output is incomplete"
    }
    # The echo line is the upstream's view, which carries the real key by design.
    for value in "$secret" "$anthropic_secret"; do
        [[ "$(grep -v '^ECHO ' <<<"$output")" != *"$value"* ]] || fail "a real credential reached the opencode sandbox"
    done
    [[ "$config_line" == *'"baseURL":"http://llm-proxy:8080/custom"'* ]] ||
        fail "opencode's custom provider does not go through the gateway"
    [[ "$config_line" == *'"apiKey":"{env:RAPUNZEL_API_KEY}"'* ]] ||
        fail "opencode's custom provider does not use the placeholder variable"
    [[ "$config_line" == *'"echo-model":'* ]] ||
        fail "opencode did not list the custom models through the gateway"
    [[ "$config_line" == *'"anthropic":{"options":{"baseURL":"http://llm-proxy:8080/anthropic/v1","apiKey":"rapunzel-gateway"}}'* ]] ||
        fail "opencode's anthropic provider does not go through the gateway"
    [[ "$echo_line" == *"\"authorization\":\"Bearer ${secret}\""* ]] ||
        fail "the gateway did not replace opencode's key with the real one"
    [[ "$echo_line" == *'"path":"/v1/echo"'* ]] || fail "the gateway did not map /custom to the upstream path"
    docker rm --force "$upstream" >/dev/null 2>&1 || true
}

# Claude Code in strict mode: its bootstrap must point the documented gateway
# settings at /anthropic with the placeholder, for an API key and for a
# subscription token, keep both out of the sandbox, and remove its entries
# again on a run outside strict mode. The upstream is fixed to
# api.anthropic.com, so the header rewrite itself is checked in test-control.sh.
claude_run() {
    env -u RAPUNZEL_NETWORK -u RAPUNZEL_BASE_URL -u RAPUNZEL_API_BASE_URL -u OPENAI_API_KEY \
        -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN \
        -u RAPUNZEL_EGRESS_ALLOW -u RAPUNZEL_EGRESS_LOGINS -u RAPUNZEL_EGRESS_ALLOW_PRIVATE \
        RAPUNZEL_ENV_FILE= \
        RAPUNZEL_HARNESS=claude \
        RAPUNZEL_IMAGE="$CLAUDE_IMAGE" \
        RAPUNZEL_VOLUME="${VOLUME}-claude" \
        "$@" \
        "${ROOT_DIR}/rapunzel" --exec "$project" node -e '
            const fs = require("node:fs"), path = require("node:path");
            const dir = "/home/agent/.claude", files = {};
            const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) {
                const f = path.join(d, e.name);
                if (e.isDirectory()) walk(f); else if (e.isFile()) files[f] = fs.readFileSync(f, "utf8"); } };
            walk(dir);
            let settings = {};
            try { settings = JSON.parse(files[path.join(dir, "settings.json")] ?? "{}"); } catch {}
            console.log("SETTINGS " + JSON.stringify(settings));
            console.log("ENV " + JSON.stringify(process.env));
            console.log("FILES " + JSON.stringify(files));
        ' 2>&1
}

check_strict_claude() {
    local kind variable placeholder secret output settings_line
    for kind in api-key oauth; do
        printf '== strict with the claude harness (%s)\n' "$kind"
        secret="pd-secret-$(random_token)"
        variable=ANTHROPIC_API_KEY placeholder=ANTHROPIC_AUTH_TOKEN
        if [[ "$kind" == oauth ]]; then variable=CLAUDE_CODE_OAUTH_TOKEN placeholder=CLAUDE_CODE_OAUTH_TOKEN; fi
        output=$(claude_run RAPUNZEL_EGRESS=strict "${variable}=${secret}")
        settings_line=$(section "$output" SETTINGS)
        [[ -n "$settings_line" && -n "$(section "$output" ENV)" && -n "$(section "$output" FILES)" ]] || {
            printf '%s\n' "$output" >&2
            fail "claude probe output is incomplete"
            continue
        }
        [[ "$output" != *"$secret"* ]] || fail "the real ${variable} reached the claude sandbox"
        jq -e --arg placeholder "$placeholder" '.env.ANTHROPIC_BASE_URL == "http://llm-proxy:8080/anthropic"
            and .env[$placeholder] == "rapunzel-gateway" and .skipWebFetchPreflight == true' \
            <<<"${settings_line#SETTINGS }" >/dev/null || fail "claude's settings do not point at the gateway (${kind})"
        printf 'CHECK PASS claude uses the gateway with %s=rapunzel-gateway\n' "$placeholder"
    done

    printf '== claude after strict mode, in allowlist mode\n'
    output=$(claude_run RAPUNZEL_EGRESS=allowlist ANTHROPIC_API_KEY=sk-dummy)
    settings_line=$(section "$output" SETTINGS)
    jq -e '(.env // {}) | has("ANTHROPIC_BASE_URL") or has("ANTHROPIC_AUTH_TOKEN") or has("CLAUDE_CODE_OAUTH_TOKEN") | not' \
        <<<"${settings_line#SETTINGS }" >/dev/null || fail "claude kept the gateway entries outside strict mode"
    jq -e 'has("skipWebFetchPreflight") | not' <<<"${settings_line#SETTINGS }" >/dev/null ||
        fail "claude kept the WebFetch preflight switch outside strict mode"
    printf 'CHECK PASS claude removed its gateway settings outside strict mode\n'
}

for mode in "${MODES[@]}"; do
    case "$mode" in
        allowlist) check_allowlist ;;
        strict)
            check_strict
            if docker image inspect "$OPENCODE_IMAGE" >/dev/null 2>&1; then
                check_strict_opencode
            else
                printf '== strict with the opencode harness: skipped, %s is not built\n' "$OPENCODE_IMAGE"
            fi
            if docker image inspect "$CLAUDE_IMAGE" >/dev/null 2>&1; then
                check_strict_claude
            else
                printf '== strict with the claude harness: skipped, %s is not built\n' "$CLAUDE_IMAGE"
            fi
            ;;
        *)
            printf 'Usage: %s [allowlist|strict]...\n' "$0" >&2
            exit 2
            ;;
    esac
done

[[ "$(egress_resources)" -le "$before" ]] || fail "an egress container or network was left behind"

if [[ "$failures" -gt 0 ]]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'PASS: %s\n' "${MODES[*]}"
