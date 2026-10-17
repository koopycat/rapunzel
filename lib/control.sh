#!/usr/bin/env bash
# Operator-only control. Pipelock owns DNS/IP safety; runtime approvals never
# widen trusted_domains. The sole host authority is the current user's metadata.

# shellcheck disable=SC2120 # Snapshot is argument-free; watch supplies --follow.
control_events() {
    # Bounded history for snapshots; watch streams new events too. Raw URLs,
    # headers and reason strings are deliberately not copied into the display.
    if docker logs --tail 2000 "$@" "$EGRESS_SIDECAR" 2>&1 |
        jq --ascii-output --unbuffered -L "$EGRESS_LIB_DIR" -Rc 'include "control"; fromjson? | block_event'; then
        return 0
    fi
    printf 'rapunzel-ctl: could not read block history; check the run and Docker daemon (output may be incomplete)\n' >&2
    return 1
}

control_pending() {
    local events known=true metadata
    # shellcheck disable=SC2119 # Snapshot intentionally omits --follow.
    events=$(control_events) || return 1
    metadata=$(cat "${RUN_DIR}/run.json") || return 1
    [[ ! -f "${RUN_DIR}/uncertain" && ! -d "${RUN_DIR}/control.lock" ]] || known=false
    jq --ascii-output -s -L "$EGRESS_LIB_DIR" --arg run "$RUN_ID" --argjson metadata "$metadata" --argjson known "$known" \
        'include "control"; pending($run; $metadata; $known)' <<<"$events"
}

control_progress() {
    if [[ "${CTL_FORMAT:-json}" == text && -t 2 ]]; then printf '%s\n' "$1" >&2 || true; fi
}

control_stop_uncertain() {
    docker stop --time 1 "$EGRESS_SIDECAR" >/dev/null 2>&1 || true
    if [[ "$(docker inspect --format '{{.State.Running}}' "$EGRESS_SIDECAR" 2>/dev/null)" == false ]]; then
        printf 'rapunzel-ctl: policy uncertain; sidecar confirmed stopped; restart this run\n' >&2 || true
    else
        printf 'rapunzel-ctl: POLICY UNCERTAIN: egress shutdown could not be confirmed; stop/restart this run before continuing\n' >&2 || true
    fi
}

control_hash() {
    # Obtain the exact normalized-config hash from the pinned binary, without
    # adding a YAML implementation on the host. This short-lived validator has
    # no network and only the sidecar volume, read-only. Nothing is published.
    local config=$1 image hash='' attempt
    image=$(docker inspect --format '{{.Image}}' "$EGRESS_SIDECAR")
    validator="rapunzel-policy-${RUN_ID}"
    docker run --detach --name "$validator" --network none --read-only --tmpfs /tmp \
        --label rapunzel.egress=1 --label "rapunzel.owner=${EGRESS_OWNER}" \
        --label "rapunzel.run=${RUN_ID}" --label rapunzel.role=validator \
        --user 65532:65532 --cap-drop=ALL --security-opt=no-new-privileges \
        --memory 512m --pids-limit 256 --env PIPELOCK_HOME=/tmp/pipelock \
        --volumes-from "${EGRESS_SIDECAR}:ro" "$image" \
        run --config "$config" --listen "0.0.0.0:${EGRESS_PROXY_PORT}" >/dev/null
    # Use the daemon's clock and nanosecond timestamp, not the host clock or a
    # second-resolution cut-off. Old acknowledgements must not confirm a retry.
    docker inspect --format '{{.Created}}' "$validator" >"${RUN_DIR}/control.lock/since"
    for attempt in $(seq 1 50); do
        hash=$(docker logs "$validator" 2>&1 | jq -Rr 'fromjson? | select(.event == "startup") | .config_hash // empty' | tail -n1)
        if [[ "$hash" =~ ^[0-9a-f]{64}$ ]]; then
            docker rm --force --volumes "$validator" >/dev/null
            validator=''
            printf '%s' "$hash"
            return
        fi
        [[ "$(docker inspect --format '{{.State.Running}}' "$validator")" == true ]] || break
        sleep 0.1
    done
    printf 'rapunzel-ctl: candidate policy validation failed; live policy unchanged\n' >&2
    return 1
}

control_replace() {
    local source=$1 image
    image=$(docker inspect --format '{{.Image}}' "$RUN_AGENT") || return 1
    # Config volume is root-owned, so a networkless, capability-free helper
    # atomically renames the staged file. It has no project or agent-state mount.
    docker run --rm --network none --read-only --user 0:0 --cap-drop=ALL \
        --security-opt=no-new-privileges --volumes-from "${EGRESS_SIDECAR}:rw" \
        --entrypoint /bin/bash "$image" -euc 'mv -T -- "$1" /config/pipelock.yaml' -- "$source" || return 1
    docker kill --signal HUP "$EGRESS_SIDECAR" >/dev/null
}

control_wait_hash() {
    local expected=$1 attempt hash since
    since=$(<"${RUN_DIR}/control.lock/since")
    for ((attempt=0; attempt<50; attempt++)); do
        hash=$(docker logs --since "$since" "$EGRESS_SIDECAR" 2>/dev/null |
            jq -Rr 'fromjson? | select(.event == "config_reload" and .status == "success") | .config_hash' | tail -n1) || return 1
        [[ "$hash" != "$expected" ]] || return 0
        sleep 0.1
    done
    return 1
}

control_update() {
    # Called directly by the CLI, never in a conditional/subshell or pipeline:
    # this process owns both the transaction and its signal/EXIT cleanup.
    local action=$1 host=$2 baseline grants owner old_hash new_hash candidate since entry image applied
    umask 077
    host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
    [[ -n "$host" ]] || { printf 'rapunzel-ctl: host must not be empty\n' >&2; exit 2; }
    [[ "$host" != *'*'* ]] || { printf 'rapunzel-ctl: runtime grants require an exact host, not a wildcard\n' >&2; exit 2; }
    egress_allow_host "$host"
    owner=$(jq -r '.owner' "${RUN_DIR}/run.json")
    [[ "${owner%/*}" == "${EGRESS_OWNER%/*}" ]] || {
        printf 'rapunzel-ctl: modify a run from its originating host\n' >&2; exit 1
    }
    # Do not reap locks using an untrusted PID or a timeout. A killed updater
    # leaves a visible lock; starting a fresh run recovers without guessing.
    mkdir -- "${RUN_DIR}/control.lock" 2>/dev/null || {
        printf 'rapunzel-ctl: policy update locked; another update is active or interrupted (restart the run if stale)\n' >&2; exit 1
    }
    validator=''
    # shellcheck disable=SC2329 # EXIT trap
    control_cleanup() {
        set +e
        trap '' HUP INT TERM
        [[ -z "$validator" ]] || docker rm --force --volumes "$validator" >/dev/null 2>&1 || true
        if [[ -f "${RUN_DIR}/uncertain" ]]; then
            control_stop_uncertain
        fi
        rm -rf -- "${RUN_DIR}/control.lock"
    }
    trap control_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    run_select "$RUN_ID"
    [[ "$(docker inspect --format '{{.State.Running}}' "$EGRESS_SIDECAR")" == true ]] || {
        printf 'rapunzel-ctl: egress sidecar is not running; restart this run\n' >&2; exit 1
    }
    [[ ! -f "${RUN_DIR}/uncertain" ]] || {
        printf 'rapunzel-ctl: prior update is uncertain; restart the run before changing policy\n' >&2; exit 1
    }
    # Confirm that our last committed generation is still the sidecar's most
    # recent accepted generation before rewriting it. Docker-admin mutations
    # are trusted but must not be silently clobbered by stale controller state.
    old_hash=$(jq -r '.policyHash' "${RUN_DIR}/run.json")
    # Transaction evidence uses all retained logs, not the bounded diagnostic
    # window. If the logging driver rotated away all evidence, refuse safely.
    applied=$(docker logs "$EGRESS_SIDECAR" 2>/dev/null |
        jq -Rr 'fromjson? | select(.event == "startup" or (.event == "config_reload" and .status == "success")) | .config_hash // empty' | tail -n1) || {
        printf 'rapunzel-ctl: cannot read accepted-policy evidence; no update attempted\n' >&2; exit 1
    }
    [[ "$applied" == "$old_hash" ]] || {
        printf 'rapunzel-ctl: active policy cannot be reconciled with run metadata; restart this run\n' >&2; exit 1
    }
    baseline=$(jq -r '.policy.baseline[]' "${RUN_DIR}/run.json")
    # Never remove startup grants; never imply revoking one child of a wildcard
    # actually blocks it. Keep that limitation explicit instead of adding denies.
    while IFS= read -r entry; do
        if [[ "$host" == "$entry" || ( "$entry" == '*.'* && ( "$host" == "${entry#*.}" || "$host" == *."${entry#*.}" ) ) ]]; then
            printf 'rapunzel-ctl: host is covered by startup policy; runtime grants cannot override it\n' >&2
            exit 2
        fi
    done <<<"$baseline"
    if [[ "$action" == allow ]]; then
        grants=$(jq --arg host "$host" '.policy.grants + [$host] | unique' "${RUN_DIR}/run.json")
    else
        grants=$(jq --arg host "$host" '.policy.grants - [$host]' "${RUN_DIR}/run.json")
    fi
    if jq -e --argjson grants "$grants" '.policy.grants == $grants' "${RUN_DIR}/run.json" >/dev/null; then
        jq -an --arg action "$action" --arg host "$host" --arg run "$RUN_ID" \
            '{changed:false,action:$action,host:$host,run:$run}' | ctl_render update
        exit
    fi
    EGRESS_HOSTS=() EGRESS_PRIVATE_HOSTS=()
    while IFS= read -r entry; do EGRESS_HOSTS+=("$entry"); done < <(jq -r --argjson grants "$grants" '(.policy.baseline + $grants) | unique[]' "${RUN_DIR}/run.json")
    while IFS= read -r entry; do EGRESS_PRIVATE_HOSTS+=("$entry"); done < <(jq -r '.policy.private[]' "${RUN_DIR}/run.json")
    candidate="${RUN_DIR}/control.lock/pipelock.yaml"
    control_progress 'Validating candidate policy...'
    allowlist_configure "${RUN_DIR}/control.lock"
    chmod 644 "$candidate"
    docker cp --quiet "$candidate" "${EGRESS_SIDECAR}:/config/candidate.yaml"
    # Avoid command substitution: validator must remain visible to the EXIT trap.
    control_hash /config/candidate.yaml >"${RUN_DIR}/control.lock/hash"
    new_hash=$(<"${RUN_DIR}/control.lock/hash")
    cp -- "${RUN_DIR}/pipelock.yaml" "${RUN_DIR}/control.lock/previous.yaml"
    chmod 644 "${RUN_DIR}/control.lock/previous.yaml"
    docker cp --quiet "${RUN_DIR}/control.lock/previous.yaml" "${EGRESS_SIDECAR}:/config/previous.yaml"
    # From here on an interrupted command may have applied. Do not falsely
    # describe the last committed metadata as the active configuration.
    printf '%s\n' "$new_hash" >"${RUN_DIR}/uncertain"
    control_progress 'Applying policy and waiting for reload confirmation...'
    control_replace /config/candidate.yaml
    if ! control_wait_hash "$new_hash"; then
        # A distinct daemon-time fence prevents a prior acknowledgement from
        # confirming rollback too. The helper is networkless and volume-less.
        image=$(docker inspect --format '{{.Image}}' "$RUN_AGENT")
        since=$(docker run --rm --network none --read-only --cap-drop=ALL --user 65534:65534 \
            --security-opt=no-new-privileges --entrypoint date "$image" -u '+%Y-%m-%dT%H:%M:%S.%NZ')
        printf '%s\n' "$since" >"${RUN_DIR}/control.lock/since"
        if control_replace /config/previous.yaml && control_wait_hash "$old_hash"; then
            rm -f -- "${RUN_DIR}/uncertain"
            printf 'rapunzel-ctl: reload not confirmed; previous policy restored\n' >&2
        else
            # EXIT cleanup attempts shutdown and reports whether it is confirmed.
            printf 'rapunzel-ctl: reload/rollback uncertain; attempting egress shutdown\n' >&2 || true
        fi
        exit 1
    fi
    jq --argjson grants "$grants" --arg hash "$new_hash" \
        '.policy.grants = $grants | .policyHash = $hash' "${RUN_DIR}/run.json" >"${RUN_DIR}/control.lock/run.json"
    cp -- "$candidate" "${RUN_DIR}/pipelock.yaml"
    mv -- "${RUN_DIR}/control.lock/run.json" "${RUN_DIR}/run.json"
    rm -f -- "${RUN_DIR}/uncertain"
    jq -nc --arg action "$action" --arg host "$host" --arg hash "$new_hash" \
        '{time:(now|todate),action:$action,host:$host,acceptedHash:$hash}' >>"${RUN_DIR}/audit.jsonl"
    jq --ascii-output -n --arg action "$action" --arg host "$host" --arg hash "$new_hash" --arg run "$RUN_ID" \
        '{changed:true,action:$action,host:$host,acceptedHash:$hash,run:$run,
          scope:"this run; new tunnels only",note:"Agent must retry. Existing tunnels are not closed. Private-address protections remain enabled."}' | ctl_render update
}
