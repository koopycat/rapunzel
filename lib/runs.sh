#!/usr/bin/env bash
# Host-only run metadata. Never mounted in the workload or read from the project.
# shellcheck disable=SC2034
RUN_ID='' RUN_DIR='' RUN_AGENT=''

require_jq() {
    command -v jq >/dev/null 2>&1 || {
        printf 'rapunzel: jq is required on the host (brew install jq / apt install jq)\n' >&2
        return 1
    }
}

runs_root() {
    local directory=${RAPUNZEL_RUNS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rapunzel/runs} mode owner
    [[ ! -L "$directory" ]] || { printf 'rapunzel: run directory must not be a symlink\n' >&2; return 1; }
    (umask 077; mkdir -p -- "$directory") || return 1
    owner=$(stat -c '%u' "$directory" 2>/dev/null || stat -f '%u' "$directory")
    mode=$(stat -c '%a' "$directory" 2>/dev/null || stat -f '%Lp' "$directory")
    [[ "$owner" == "$(id -u)" && "$mode" == 700 ]] || {
        printf 'rapunzel: run directory must belong to you and have mode 700 (path redacted)\n' >&2
        return 1
    }
    RUNS_ROOT=$(cd -- "$directory" && pwd -P)
}

run_register() {
    umask 077
    runs_root
    case "$RUNS_ROOT/" in
        "$PROJECT_DIR/"*)
            printf 'rapunzel: host run metadata must be outside the mounted project; set RAPUNZEL_RUNS_DIR\n' >&2
            return 1 ;;
    esac
    case "$PROJECT_DIR/" in
        "$RUNS_ROOT/"*)
            printf 'rapunzel: the run registry cannot be used as a project\n' >&2
            return 1 ;;
    esac
    [[ "$PROJECT_DIR" != / ]] || { printf 'rapunzel: cannot mount the host root as a project\n' >&2; return 1; }
    RUN_ID=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
    RUN_AGENT="rapunzel-agent-${RUN_ID}"
    RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
    (umask 077; mkdir -- "$RUN_DIR")
    local daemon
    daemon=$(docker info --format '{{.ID}}')
    jq -n --arg run "$RUN_ID" --arg agent "$RUN_AGENT" --arg project "$PROJECT_DIR" \
        --arg harness "$H_NAME" --arg image "$IMAGE" --arg volume "$VOLUME" \
        --arg egress "$EGRESS" --arg daemon "$daemon" --arg owner "$EGRESS_OWNER" \
        '{run:$run,agent:$agent,project:$project,harness:$harness,image:$image,volume:$volume,
          egress:$egress,daemon:$daemon,owner:$owner,status:"starting"}' >"${RUN_DIR}/run.json"
    chmod 600 "${RUN_DIR}/run.json"
}

run_publish() {
    local hash='' events=''
    if [[ "$EGRESS" == allowlist ]]; then
        events=$(docker logs "$EGRESS_SIDECAR" 2>&1)
        hash=$(jq -Rr 'fromjson? | select(.event == "startup") | .config_hash // empty' <<<"$events" | tail -n1)
        [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { printf 'rapunzel: proxy startup did not report a policy hash\n' >&2; return 1; }
    fi
    jq --arg sidecar "$EGRESS_SIDECAR" --arg network "$NETWORK" --arg outbound "$EGRESS_OUTBOUND" \
        --arg hash "$hash" --slurpfile policy "${RUN_DIR}/policy.json" --slurpfile config "${RUN_DIR}/config.json" \
        '. + {sidecar:$sidecar,network:$network,outbound:$outbound,policy:$policy[0],policyHash:$hash,
               credentials:$config[0].credentials,providerKeysEnterAgent:$config[0].providerKeysEnterAgent,status:"running"}' \
        "${RUN_DIR}/run.json" >"${RUN_DIR}/run.next"
    mv -- "${RUN_DIR}/run.next" "${RUN_DIR}/run.json"
    printf 'rapunzel: run %s (%s); inspect with rapunzel-ctl inspect %s\n' "$RUN_ID" "$H_NAME" "$RUN_ID" >&2
}

run_forget() {
    [[ -z "$RUN_DIR" ]] || rm -rf -- "$RUN_DIR"
}

# Freeze a unique prefix from the caller's registry before selecting resources.
# Stale/foreign/corrupt matches still count: do not silently choose another run.
run_resolve() {
    local prefix=$1 directory matches=()
    [[ "$prefix" =~ ^[0-9a-f]{8,24}$ ]] || {
        printf 'rapunzel-ctl: use a full run ID or unique 8-24 lowercase hex prefix\n' >&2; return 1
    }
    runs_root || return 1
    for directory in "$RUNS_ROOT"/"$prefix"*; do
        [[ -d "$directory" && "${directory##*/}" =~ ^[0-9a-f]{24}$ ]] || continue
        matches+=("${directory##*/}")
    done
    if [[ ${#matches[@]} -eq 0 ]]; then
        printf 'rapunzel-ctl: no registry run matches this selector; the run may have ended (check runs)\n' >&2
        return 1
    elif [[ ${#matches[@]} -ne 1 ]]; then
        printf 'rapunzel-ctl: selector matches %s registry records; use a full run ID from runs\n' "${#matches[@]}" >&2
        return 1
    fi
    RUN_ID=${matches[0]}
}

# Read current-user metadata and verify daemon/resource labels before acting.
run_select() {
    local id=${1:?run ID required} actual daemon
    run_resolve "$id" || return 1
    id=$RUN_ID
    RUN_ID=$id RUN_DIR="${RUNS_ROOT}/${id}" RUN_AGENT="rapunzel-agent-${id}"
    [[ -d "$RUN_DIR" && ! -L "$RUN_DIR" && -f "${RUN_DIR}/run.json" && ! -L "${RUN_DIR}/run.json" ]] || {
        printf 'rapunzel-ctl: unknown run: %s\n' "$id" >&2; return 1
    }
    daemon=$(docker info --format '{{.ID}}') || return 1
    jq -e --arg id "$id" --arg daemon "$daemon" --arg agent "$RUN_AGENT" \
        '.run == $id and .daemon == $daemon and .agent == $agent and .status == "running"' \
        "${RUN_DIR}/run.json" >/dev/null || { printf 'rapunzel-ctl: run belongs to another daemon or is not ready\n' >&2; return 1; }
    actual=$(docker inspect --format '{{index .Config.Labels "rapunzel.run"}} {{.State.Running}}' "$RUN_AGENT" 2>/dev/null) || {
        printf 'rapunzel-ctl: run is no longer active\n' >&2; return 1
    }
    [[ "$actual" == "$id true" ]] || { printf 'rapunzel-ctl: agent stopped or label mismatch\n' >&2; return 1; }
    EGRESS=$(jq -r '.egress' "${RUN_DIR}/run.json") || return 1
    EGRESS_SIDECAR=$(jq -r '.sidecar' "${RUN_DIR}/run.json") || return 1
    if [[ "$EGRESS" != open ]]; then
        actual=$(docker inspect --format '{{index .Config.Labels "rapunzel.run"}}' "$EGRESS_SIDECAR") || return 1
        [[ "$actual" == "$id" ]] || { printf 'rapunzel-ctl: sidecar label mismatch\n' >&2; return 1; }
    fi
}

# Return JSON to the safe renderer; labels alone do not authorize discovery.
run_list() {
    local directory id daemon actual
    runs_root || return 1
    daemon=$(docker info --format '{{.ID}}') || return 1
    for directory in "$RUNS_ROOT"/*; do
        id=${directory##*/}
        [[ "$id" =~ ^[0-9a-f]{24}$ && -d "$directory" && ! -L "$directory" && -f "$directory/run.json" && ! -L "$directory/run.json" ]] || continue
        jq -e --arg id "$id" --arg daemon "$daemon" \
            '.run == $id and .agent == ("rapunzel-agent-" + $id) and .daemon == $daemon and .status == "running"' \
            "$directory/run.json" >/dev/null 2>&1 || continue
        actual=$(docker inspect --format '{{index .Config.Labels "rapunzel.run"}} {{.State.Running}}' "rapunzel-agent-${id}" 2>/dev/null) || continue
        [[ "$actual" == "$id true" ]] || continue
        jq '{run,project,harness,egress,status}' "$directory/run.json" || return 1
    done | jq --ascii-output -s .
}
