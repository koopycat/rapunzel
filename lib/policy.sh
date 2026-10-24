#!/usr/bin/env bash
# Shared policy construction for both the launcher and --config inspection.
# shellcheck disable=SC2034,SC2153,SC2154 # Profile and launcher supply the arrays.
EGRESS_REASONS=()

policy_host() {
    egress_allow_host "$1" || return 1
    EGRESS_REASONS+=("$1: $2")
}

policy_collect() {
    local host login before index entry id key_name origin
    EGRESS_HOSTS=() EGRESS_PRIVATE_HOSTS=() EGRESS_REASONS=()
    [[ "$EGRESS" != open ]] || return 0
    if [[ "$EGRESS" == strict ]]; then
        # Hosts the harness's tools may reach (package registries, git hosts)
        # through Pipelock next to the gateway. Model APIs stay gateway-only.
        IFS=$', \t' read -r -a extra_hosts <<<"${RAPUNZEL_EGRESS_ALLOW:-}"
        for host in ${extra_hosts[@]+"${extra_hosts[@]}"}; do policy_host "$host" 'RAPUNZEL_EGRESS_ALLOW (tools)'; done
        policy_refuse_provider_hosts
        return
    fi
    for host in ${H_EGRESS_HOSTS[@]+"${H_EGRESS_HOSTS[@]}"}; do policy_host "$host" "profile ${H_NAME}"; done
    for entry in "${GATEWAY_BUILTINS[@]}"; do
        read -r id key_name origin _ <<<"$entry"
        [[ -z "$(runtime_value "$key_name")" ]] || policy_host "${origin#https://}" "${key_name} present"
    done
    if [[ -n "$custom_url" ]]; then
        host=$(url_host "$custom_url") || return 1
        policy_host "$host" 'custom provider URL' || return 1
    fi
    IFS=$', \t' read -r -a logins <<<"${RAPUNZEL_EGRESS_LOGINS:-}"
    for login in ${logins[@]+"${logins[@]}"}; do
        before=${#EGRESS_HOSTS[@]}
        egress_allow_login "$login"
        for ((index=before; index<${#EGRESS_HOSTS[@]}; index++)); do
            EGRESS_REASONS+=("${EGRESS_HOSTS[index]}: login ${login}")
        done
    done
    IFS=$', \t' read -r -a extra_hosts <<<"${RAPUNZEL_EGRESS_ALLOW:-}"
    for host in ${extra_hosts[@]+"${extra_hosts[@]}"}; do policy_host "$host" RAPUNZEL_EGRESS_ALLOW; done
    IFS=$', \t' read -r -a private_hosts <<<"${RAPUNZEL_EGRESS_ALLOW_PRIVATE:-}"
    for host in ${private_hosts[@]+"${private_hosts[@]}"}; do
        egress_allow_private_host "$host"
        EGRESS_REASONS+=("$host: RAPUNZEL_EGRESS_ALLOW_PRIVATE")
    done
}

# In strict mode an allowed host must not lead to a provider API: there the
# agent could use a key of its own and send data out under an attacker's
# account, which is what the gateway's overwritten headers prevent.
policy_refuse_provider_hosts() {
    local entry origin provider pattern suffix providers=()
    for entry in "${GATEWAY_BUILTINS[@]}"; do
        read -r _ _ origin _ <<<"$entry"
        providers+=("${origin#https://}")
    done
    if [[ -n "$custom_url" ]]; then
        providers+=("$(url_host "$custom_url")") || return 1
    fi
    for pattern in ${EGRESS_HOSTS[@]+"${EGRESS_HOSTS[@]}"}; do
        for provider in "${providers[@]}"; do
            suffix=${pattern#\*.}
            if [[ "$pattern" == "$provider" ]] ||
                [[ "$pattern" == \*.* && ("$provider" == "$suffix" || "$provider" == *".$suffix") ]]; then
                printf 'rapunzel: RAPUNZEL_EGRESS_ALLOW entry %s covers the provider API host %s; with RAPUNZEL_EGRESS=strict that host is reachable only through the gateway\n' \
                    "$pattern" "$provider" >&2
                return 1
            fi
        done
    done
}

policy_json() {
    local hosts private reasons
    hosts=$(printf '%s\n' ${EGRESS_HOSTS[@]+"${EGRESS_HOSTS[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')
    private=$(printf '%s\n' ${EGRESS_PRIVATE_HOSTS[@]+"${EGRESS_PRIVATE_HOSTS[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')
    reasons=$(printf '%s\n' ${EGRESS_REASONS[@]+"${EGRESS_REASONS[@]}"} | jq -Rsc 'split("\n") | map(select(length > 0))')
    jq -n --argjson baseline "$hosts" --argjson private "$private" --argjson reasons "$reasons" \
        '{baseline:$baseline,private:$private,reasons:$reasons,grants:[]}'
}

config_report() {
    local policy credentials name source
    policy=$(policy_json)
    credentials='[]'
    for name in "${env_allowlist[@]}" ${gateway_consumed[@]+"${gateway_consumed[@]}"}; do
        [[ "$name" != RAPUNZEL_API_KEY_VARIABLE ]] || continue
        if [[ "$name" != "${key_variable:-RAPUNZEL_API_KEY}" ]]; then
            case "$name" in *KEY* | *TOKEN*) ;; *) continue ;; esac
        fi
        [[ -n "$(runtime_value "$name")" ]] || continue
        source='env-file'
        [[ -z "${!name+x}" ]] || source='environment'
        credentials=$(jq --arg name "$name" --arg source "$source" \
            '. + [{name:$name,present:true,source:$source}] | unique_by(.name)' <<<"$credentials")
    done
    jq --ascii-output -n --arg project "$PROJECT_DIR" --arg harness "$H_NAME" --arg image "$IMAGE" --arg volume "$VOLUME" \
        --arg mode "$EGRESS" --arg modeSource "${RAPUNZEL_EGRESS+environment}" --arg envfile "${RAPUNZEL_ENV_FILE:-}" \
        --arg network "$NETWORK" --argjson policy "$policy" --argjson credentials "$credentials" \
        '{project:$project,harness:$harness,image:$image,volume:$volume,egress:$mode,
          egressSource:(if $modeSource == "" then "default" else $modeSource end),envFile:$envfile,
          network:(if $mode == "open" then $network else "per-run isolated internal network" end),
          policy:$policy,credentials:$credentials,providerKeysEnterAgent:($mode != "strict"),
          note:"Credential values and custom URL paths are never included. OAuth state is not inspected."}'
}
