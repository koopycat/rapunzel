#!/usr/bin/env bash
set -Eeuo pipefail
# Live controller integration through the real launcher and pinned Pipelock.
# Uses public HTTPS hosts, but no API credentials. Run verify-egress.sh as well.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
IMAGE=${RAPUNZEL_IMAGE:-rapunzel}
project=$(mktemp -d "${ROOT}/.rapunzel-verify.XXXXXX")
runs=$(mktemp -d "${TMPDIR:-/tmp}/rapunzel-runs-test.XXXXXX")
volume="rapunzel-control-check-$$"
ids=() pids=()
cleanup() {
    set +e
    for id in ${ids[@]+"${ids[@]}"}; do docker stop --time 1 "rapunzel-agent-${id}" >/dev/null 2>&1; done
    for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid"; done
    docker volume rm "$volume" >/dev/null 2>&1
    rm -rf -- "$project" "$runs"
}
trap cleanup EXIT
ctl() { RAPUNZEL_RUNS_DIR="$runs" "$ROOT/rapunzel-ctl" --json "$@"; }
start() {
    local number=$1 id attempt
    env -u RAPUNZEL_NETWORK -u RAPUNZEL_API_BASE_URL -u RAPUNZEL_BASE_URL \
        -u ANTHROPIC_API_KEY -u OPENAI_API_KEY -u RAPUNZEL_EGRESS_ALLOW_PRIVATE \
        -u RAPUNZEL_EGRESS_LOGINS RAPUNZEL_ENV_FILE= RAPUNZEL_IMAGE="$IMAGE" \
        RAPUNZEL_RUNS_DIR="$runs" RAPUNZEL_VOLUME="$volume" RAPUNZEL_EGRESS=allowlist \
        RAPUNZEL_EGRESS_ALLOW=api.openai.com \
        "$ROOT/rapunzel" --exec "$project" sleep 300 >"$project/run-${number}.log" 2>&1 &
    pids+=("$!")
    for ((attempt=0; attempt<100; attempt++)); do
        id=$(sed -n 's/rapunzel: run \([0-9a-f]*\) .*/\1/p' "$project/run-${number}.log")
        if [[ -n "$id" ]] && docker inspect "rapunzel-agent-${id}" >/dev/null 2>&1; then
            ids+=("$id"); return
        fi
        sleep 0.2
    done
    cat "$project/run-${number}.log" >&2
    printf 'run did not start\n' >&2; return 1
}
status() {
    docker exec "rapunzel-agent-$1" curl -I --max-time 15 --silent --show-error "https://$2/" >"$project/curl.log" 2>&1
}
refused() { if status "$1" "$2"; then printf 'FAIL: unexpectedly reached %s\n' "$2" >&2; exit 1; fi; }

start 1; first=${ids[0]}
start 2; second=${ids[1]}
ctl runs | jq -e --arg id "$first" 'any(.run == $id)' >/dev/null
ctl inspect "$first" | jq -e '.harness == "pi" and .egress == "allowlist"' >/dev/null
refused "$first" example.com
ctl egress pending "${first:0:8}" | jq -e 'any(.destinations[]; .host == "example.com" and .approvalCandidate and .coverage == "not-covered")' >/dev/null
RAPUNZEL_RUNS_DIR="$runs" "$ROOT/rapunzel-ctl" --format=text egress allow "${first:0:8}" example.com >"$project/text-allow"
grep -q 'Policy reload confirmed' "$project/text-allow"
ctl egress pending "$first" | jq -e 'any(.destinations[]; .host == "example.com" and .coverage == "runtime" and (.approvalCandidate | not))' >/dev/null
status "$first" example.com
refused "$second" example.com
ctl egress revoke "$first" example.com
refused "$first" example.com
# Recheck TLS binding and direct routes after live policy changes, not only on
# startup config. The main egress suite separately runs a real host canary.
docker exec "rapunzel-agent-${first}" node --input-type=module \
    -e "$(<"$ROOT/lib/egress-probe.mjs")" allowlist 39127 api.openai.com >"$project/post-grant-probe"
grep '^CHECK ' "$project/post-grant-probe"
if grep -q '^CHECK FAIL' "$project/post-grant-probe"; then exit 1; fi
ctl egress allow "$first" example.com
ctl egress revoke "$first" example.com
refused "$first" example.com

# Concurrent operators cannot drop one another's grants. One may be refused
# while the lock is held; it must be safe to retry that explicit request.
ctl egress allow "$first" example.com >"$project/update-1" & update_one=$!
ctl egress allow "$first" www.iana.org >"$project/update-2" 2>&1 & update_two=$!
one_ok=true; two_ok=true
wait "$update_one" || one_ok=false
wait "$update_two" || two_ok=false
# Wait for both operators before retrying the one refused by the lock.
[[ "$one_ok" == true ]] || ctl egress allow "$first" example.com
[[ "$two_ok" == true ]] || ctl egress allow "$first" www.iana.org
ctl egress show "$first" | jq -e '.grants | length == 2' >/dev/null
ctl egress revoke "$first" example.com
ctl egress revoke "$first" www.iana.org

for host in '*.example.com' '1.1.1.1' 'example.com:443' 'api.openai.com'; do
    if ctl egress allow "$first" "$host" >/dev/null 2>&1; then printf 'FAIL: runtime approval accepted %s\n' "$host" >&2; exit 1; fi
done
ctl egress allow "$first" host.docker.internal
refused "$first" host.docker.internal
ctl egress revoke "$first" host.docker.internal

# Prefixes resolve inside caller-owned metadata; stale collisions must not
# select a different live run. Full IDs remain usable in that case.
ctl inspect "${first:0:8}" | jq -e --arg id "$first" '.run == $id' >/dev/null
collision="${first:0:8}0000000000000000"
[[ "$collision" != "$first" ]]
mkdir "$runs/$collision"
if ctl inspect "${first:0:8}" >/dev/null 2>&1; then exit 1; fi
rmdir "$runs/$collision"
ctl inspect "$first" | jq -e '.providerKeysEnterAgent == true and .credentials == []' >/dev/null

# Flood only blocked CONNECT events, not application requests. A busy workload
# must not push accepted-generation evidence out of the diagnostic tail and
# prevent the host from granting/revoking a destination.
docker exec "rapunzel-agent-${first}" node --input-type=module -e '
import net from "node:net";
const proxy = new URL(process.env.HTTPS_PROXY);
let remaining = 2100;
async function block() {
  await new Promise((resolve, reject) => {
    const socket = net.connect(Number(proxy.port), proxy.hostname);
    socket.setTimeout(10000, () => socket.destroy(new Error("timeout")));
    socket.once("connect", () => socket.write("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"));
    socket.once("data", data => { socket.destroy(); data.toString().includes("403") ? resolve() : reject(new Error("not blocked")); });
    socket.once("error", reject);
  });
}
await Promise.all(Array.from({length:10}, async () => { while (remaining-- > 0) await block(); }));'
[[ "$(docker logs --tail 2000 "rapunzel-egress-${first}" 2>&1 | jq -Rsc '[split("\n")[] | fromjson? | select(.event == "startup" or .event == "config_reload")] | length')" == 0 ]]
ctl egress allow "$first" example.com
ctl egress revoke "$first" example.com

# A consumer closing stdout after the transaction starts must not skip cleanup
# or imply the policy was unchanged. Inspect remains the source of committed
# state even when reporting the successful update hits a broken pipe.
if ctl egress allow "$first" example.com | head -n 0; then
    printf 'FAIL: closed output pipe unexpectedly reported success\n' >&2; exit 1
fi
[[ ! -d "$runs/$first/control.lock" && ! -f "$runs/$first/uncertain" ]]
ctl egress show "$first" | jq -e '.grants == ["example.com"]' >/dev/null
ctl egress revoke "$first" example.com

# Inject a broken candidate at the Docker delivery boundary: validation must
# fail before the running policy is replaced. The shim is test-only.
mkdir "$project/bin"
real_docker=$(command -v docker)
cat >"$project/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${CONTROL_FAULT:-}" == invalid && "$1" == cp && "${*: -1}" == *:/config/candidate.yaml ]]; then
    printf 'not_a_supported_setting: true\n' >"$CONTROL_BAD_CONFIG"
    exec "$CONTROL_REAL_DOCKER" cp --quiet "$CONTROL_BAD_CONFIG" "${*: -1}"
fi
if [[ "${CONTROL_FAULT:-}" == noack && "$1" == logs && " $* " == *' --since '* ]]; then
    "$CONTROL_REAL_DOCKER" "$@" 2>&1 | grep -v '"event":"config_reload"' || true
    exit
fi
if [[ "${CONTROL_FAULT:-}" == logerror && "$1" == logs ]]; then
    printf 'test log read error\n' >&2
    exit 1
fi
if [[ "${CONTROL_FAULT:-}" == interrupt-before && "$1" == cp && "${*: -1}" == *:/config/candidate.yaml ]] ||
   [[ "${CONTROL_FAULT:-}" == interrupt-after && "$1" == kill && " $* " == *' HUP '* ]]; then
    "$CONTROL_REAL_DOCKER" "$@"
    : >"$CONTROL_SIGNAL_MARKER"
    sleep 2
    exit
fi
exec "$CONTROL_REAL_DOCKER" "$@"
EOF
chmod +x "$project/bin/docker"
if PATH="$project/bin:$PATH" CONTROL_REAL_DOCKER="$real_docker" CONTROL_FAULT=invalid \
    CONTROL_BAD_CONFIG="$project/invalid.yaml" ctl egress allow "$first" example.com >"$project/invalid.log" 2>&1; then
    printf 'FAIL: invalid candidate was accepted\n' >&2; exit 1
fi
refused "$first" example.com
ctl egress show "$first" | jq -e '.grants == []' >/dev/null
[[ "$(docker inspect --format '{{.State.Running}}' "rapunzel-egress-${first}")" == true ]]

# A failed history read is an error, not an empty pending snapshot.
if PATH="$project/bin:$PATH" CONTROL_REAL_DOCKER="$real_docker" CONTROL_FAULT=logerror \
    ctl egress pending "$first" >"$project/logerror.log" 2>&1; then exit 1; fi
grep -q 'could not read block history' "$project/logerror.log"

interrupt_update() {
    local phase=$1 controller attempt
    rm -f "$project/signal-marker"
    env PATH="$project/bin:$PATH" CONTROL_REAL_DOCKER="$real_docker" CONTROL_FAULT="interrupt-$phase" \
        CONTROL_SIGNAL_MARKER="$project/signal-marker" RAPUNZEL_RUNS_DIR="$runs" \
        "$ROOT/rapunzel-ctl" --json egress allow "$first" example.com >"$project/interrupt-$phase.log" 2>&1 &
    controller=$!
    for ((attempt=0; attempt<100; attempt++)); do
        [[ ! -f "$project/signal-marker" ]] || break
        sleep 0.1
    done
    [[ -f "$project/signal-marker" ]] || { wait "$controller"; printf 'FAIL: signal test never reached %s\n' "$phase" >&2; return 1; }
    # Signal only the CLI PID, not its process group. It must own cleanup rather
    # than leave an orphan transaction subshell to finish after the CLI exits.
    kill -TERM "$controller"
    local result=0
    wait "$controller" || result=$?
    [[ "$result" == 143 && ! -d "$runs/$first/control.lock" ]]
}
interrupt_update before
[[ ! -f "$runs/$first/uncertain" ]]
[[ "$(docker inspect --format '{{.State.Running}}' "rapunzel-egress-${first}")" == true ]]
ctl egress show "$first" | jq -e '.grants == []' >/dev/null

# Lost acknowledgements must not report success or leave uncertain egress
# running. This intentionally stops the second run's sidecar after rollback
# also cannot be confirmed.
if PATH="$project/bin:$PATH" CONTROL_REAL_DOCKER="$real_docker" CONTROL_FAULT=noack \
    ctl egress allow "$second" example.com >"$project/noack.log" 2>&1; then
    printf 'FAIL: missing acknowledgement was treated as success\n' >&2; exit 1
fi
[[ "$(docker inspect --format '{{.State.Running}}' "rapunzel-egress-${second}")" == false ]]
ctl inspect "$second" | jq -e '.policyUncertain == true' >/dev/null
refused "$second" example.com

# The workload cannot see policy state or gain a Docker control channel.
docker exec "rapunzel-agent-${first}" bash -c 'test ! -S /var/run/docker.sock && test ! -d "$1" && test ! -d /config' -- "$runs"
interrupt_update after
[[ "$(docker inspect --format '{{.State.Running}}' "rapunzel-egress-${first}")" == false ]]
ctl inspect "$first" | jq -e '.policyUncertain' >/dev/null
grep -q 'sidecar confirmed stopped' "$project/interrupt-after.log"
refused "$first" example.com
for id in "$first" "$second"; do docker stop --time 1 "rapunzel-agent-${id}" >/dev/null; done
for pid in "${pids[@]}"; do wait "$pid" || true; done
[[ ! -d "$runs/$first" && ! -d "$runs/$second" ]]
[[ "$(docker ps --all --quiet --filter "label=rapunzel.run=${first}" | wc -l | tr -d ' ')" == 0 ]]
printf 'PASS: grants/revoke, prefixes, grouped history, busy logs, isolation, concurrency, faults, CLI-PID interruption, and cleanup\n'
