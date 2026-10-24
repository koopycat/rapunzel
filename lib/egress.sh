#!/usr/bin/env bash
# shellcheck disable=SC2034 # EGRESS_*/GATEWAY_* variables are read by the sourcing script
# Egress control: per-run networks plus one sidecar that is pi's only way out.
#
# Source this file from rapunzel. It defines:
#   egress_networks_create - create the per-run internal and outbound networks
#   egress_allow_host      - add a validated host to the allowlist
#   egress_allow_login     - add the hosts a pi /login provider needs
#   egress_allow_private_host - add an exact host that may resolve privately
#   allowlist_configure    - render the Pipelock config
#   allowlist_start        - start Pipelock, the CONNECT allowlist proxy
#   gateway_configure      - render the Caddy credential gateway config
#   gateway_start          - start the Caddy credential gateway
#   egress_stop            - remove the sidecar and both networks again
#
# pi joins only EGRESS_NETWORK. That network is --internal with an isolated
# bridge gateway, so pi has no route off it, no upstream DNS, and no address
# on the host side of the bridge. The sidecar also joins EGRESS_OUTBOUND, a
# per-run bridge of its own, so it never shares a network with unrelated
# containers. See docs/egress.md for the design and its decisions.

EGRESS_PROXY_IMAGE=${RAPUNZEL_EGRESS_PROXY_IMAGE:-ghcr.io/luckypipewrench/pipelock:3.7.1@sha256:20402f0df5d2fb3ef50dadd8f70f758b49d878c3d90b2797eaadcb0f2f0c2ebd}
EGRESS_PROXY_ALIAS=egress
EGRESS_PROXY_PORT=8888
EGRESS_PROXY_URL="http://${EGRESS_PROXY_ALIAS}:${EGRESS_PROXY_PORT}"

GATEWAY_IMAGE=${RAPUNZEL_GATEWAY_IMAGE:-caddy:2.11.7-alpine@sha256:eb4d35b7452d1ab6171fbdbe8d9275b2301dad6dad92115d91e19fb9b24d510f}
GATEWAY_ALIAS=llm-proxy
GATEWAY_PORT=8080
GATEWAY_URL="http://${GATEWAY_ALIAS}:${GATEWAY_PORT}"
# Placeholder the agent sees wherever a provider expects a key.
GATEWAY_DUMMY_KEY=rapunzel-gateway

# Built-in providers with a fixed API host, one per line: provider id (pi's,
# also the gateway route /<id>), key variable, upstream origin, upstream path
# prefix ("-" for none), and how the key is sent. A present key opens the
# origin's host in allowlist mode and adds the route to the strict gateway.
# The openrouter prefix "v1:/api,/api/v1" sends /v1/* (Anthropic Messages
# models) to /api and everything else (OpenAI-compatible models) to /api/v1,
# because pi uses both base URLs and one provider-level override cannot.
GATEWAY_BUILTINS=(
    "anthropic ANTHROPIC_API_KEY https://api.anthropic.com - x-api-key"
    "openai OPENAI_API_KEY https://api.openai.com - bearer"
    "openrouter OPENROUTER_API_KEY https://openrouter.ai v1:/api,/api/v1 bearer"
    "google GEMINI_API_KEY https://generativelanguage.googleapis.com - x-goog-api-key"
    "groq GROQ_API_KEY https://api.groq.com /openai bearer"
    "mistral MISTRAL_API_KEY https://api.mistral.ai - bearer"
    "deepseek DEEPSEEK_API_KEY https://api.deepseek.com - bearer"
    "xai XAI_API_KEY https://api.x.ai - bearer"
)

EGRESS_NETWORK=""
EGRESS_OUTBOUND=""
EGRESS_SIDECAR=""
EGRESS_HOSTS=()
EGRESS_PRIVATE_HOSTS=()
EGRESS_LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
GATEWAY_PROVIDERS=""
GATEWAY_CUSTOM=false
GATEWAY_ANTHROPIC_AUTH=""

# Every per-run resource names its launcher, so a later run can remove what a
# killed one left behind (D13).
EGRESS_OWNER="$(hostname 2>/dev/null || uname -n)/$$"

# Remove sidecars and networks whose launcher on this host no longer runs. A
# launcher killed outright, or one whose terminal closed mid-cleanup, cannot
# remove them itself. A live PID, even a reused one, keeps its resources.
egress_sweep_stale() {
    local host=${EGRESS_OWNER%/*} kind owner pid name
    for kind in container network; do
        while read -r name owner; do
            [[ -n "$name" && "${owner%/*}" == "$host" ]] || continue
            pid=${owner##*/}
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            ps -p "$pid" >/dev/null 2>&1 && continue
            if [[ "$kind" == container ]]; then
                docker rm --force --volumes "$name" >/dev/null 2>&1 || true
            else
                docker network rm "$name" >/dev/null 2>&1 || true
            fi
        done < <(
            if [[ "$kind" == container ]]; then
                docker ps --all --filter label=rapunzel.egress=1 \
                    --format '{{.Names}} {{.Label "rapunzel.owner"}}' 2>/dev/null
            else
                docker network ls --filter label=rapunzel.egress=1 \
                    --format '{{.Name}} {{.Label "rapunzel.owner"}}' 2>/dev/null
            fi
        )
    done
}

egress_networks_create() {
    local run_id
    run_id=${RUN_ID:-$(date +%s)-$$-${RANDOM}}
    egress_sweep_stale

    # Isolated gateway mode (Docker Engine 28+) leaves the bridge without a
    # host-side address, so pi cannot reach services on the host.
    EGRESS_NETWORK="rapunzel-${run_id}"
    if ! docker network create --internal \
        --opt com.docker.network.bridge.gateway_mode_ipv4=isolated \
        --opt com.docker.network.bridge.gateway_mode_ipv6=isolated \
        --label rapunzel.egress=1 \
        --label "rapunzel.run=${run_id}" \
        --label "rapunzel.owner=${EGRESS_OWNER}" \
        "$EGRESS_NETWORK" >/dev/null; then
        EGRESS_NETWORK=""
        printf 'rapunzel: could not create an isolated internal network; RAPUNZEL_EGRESS needs Docker Engine 28 or newer\n' >&2
        return 1
    fi

    EGRESS_OUTBOUND="rapunzel-${run_id}-out"
    if ! docker network create \
        --opt com.docker.network.bridge.enable_icc=false \
        --label rapunzel.egress=1 \
        --label "rapunzel.run=${run_id}" \
        --label "rapunzel.owner=${EGRESS_OWNER}" \
        "$EGRESS_OUTBOUND" >/dev/null; then
        EGRESS_OUTBOUND=""
        printf 'rapunzel: could not create the outbound network for the egress sidecar\n' >&2
        return 1
    fi
    EGRESS_SIDECAR="rapunzel-egress-${run_id}"
}

# Add one allowlist entry after checking it is a plain DNS name.
egress_valid_host() {
    jq -en -L "$EGRESS_LIB_DIR" --arg host "$1" 'include "control"; $host | valid_host(true)' >/dev/null
}

egress_allow_host() {
    local host
    host=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ -n "$host" ]] || return 0
    if ! egress_valid_host "$host"; then
        printf 'rapunzel: not an allowable DNS host name (value redacted; labels max 63, name max 253 characters)\n' >&2
        return 1
    fi
    local known
    for known in ${EGRESS_HOSTS[@]+"${EGRESS_HOSTS[@]}"}; do
        [[ "$known" != "$host" ]] || return 0
    done
    EGRESS_HOSTS+=("$host")
}

# Allow an exact host that resolves to a private address, such as a model
# router on the local network. Pipelock otherwise refuses private and
# loopback destinations after DNS resolution, allowlisted or not. Only exact
# names: whoever controls a name's DNS decides where it points.
egress_allow_private_host() {
    if [[ "$1" == *'*'* ]]; then
        printf 'rapunzel: RAPUNZEL_EGRESS_ALLOW_PRIVATE takes exact host names, not wildcards (value redacted)\n' >&2
        return 1
    fi
    egress_allow_host "$1" || return 1
    EGRESS_PRIVATE_HOSTS+=("$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')")
}

# Add the hosts that a pi /login (OAuth) provider uses for its model API and
# token refresh. Names are pi provider IDs, as in auth.json. Taken from pi-ai
# 0.99.1 (auth/oauth/*, providers/*); review them when pi changes providers. The set comes from the host's
# environment, never from auth.json: pi controls that file and could widen
# its own allowlist through it.
egress_allow_login() {
    case "$1" in
        # "Sign in with ChatGPT": the subscription token is used directly
        # against api.openai.com.
        openai) egress_allow_host api.openai.com && egress_allow_host auth.openai.com ;;
        # pi's legacy ChatGPT Plus/Pro login, served from chatgpt.com.
        openai-codex) egress_allow_host chatgpt.com && egress_allow_host auth.openai.com ;;
        anthropic) egress_allow_host api.anthropic.com && egress_allow_host platform.claude.com ;;
        # The model host comes from the token (individual, business, or
        # enterprise). api.github.com also exposes GitHub's whole REST API.
        github-copilot) egress_allow_host api.github.com && egress_allow_host '*.githubcopilot.com' ;;
        *)
            printf 'rapunzel: unknown RAPUNZEL_EGRESS_LOGINS entry: %s (supported: openai, openai-codex, anthropic, github-copilot)\n' \
                "$1" >&2
            return 1
            ;;
    esac
}

# Print the host of an http(s) URL, or fail.
url_host() {
    if [[ ! "$1" =~ ^https?://([^/?#:@[:space:]]+)(:[0-9]+)?(/[^?#[:space:]]*)?$ ]]; then
        printf 'rapunzel: RAPUNZEL_API_BASE_URL is not an http(s) URL without credentials, query or fragment (value redacted)\n' >&2
        return 1
    fi
    printf '%s' "${BASH_REMATCH[1]}"
}

# Render the Pipelock config into DIR from EGRESS_HOSTS.
allowlist_configure() {
    local dir=${1:?allowlist_configure requires a directory}
    local host
    if [[ ${#EGRESS_HOSTS[@]} -eq 0 ]]; then
        printf 'rapunzel: RAPUNZEL_EGRESS=allowlist needs at least one host: set ANTHROPIC_API_KEY, OPENAI_API_KEY, RAPUNZEL_API_BASE_URL, RAPUNZEL_EGRESS_LOGINS, RAPUNZEL_EGRESS_ALLOW, or RAPUNZEL_EGRESS_ALLOW_PRIVATE\n' >&2
        return 1
    fi
    {
        printf '%s\n' \
            'version: 1' \
            '# Only api_allowlist hosts are reachable.' \
            'mode: strict' \
            'enforce: true' \
            'explain_blocks: false' \
            'api_allowlist:'
        for host in "${EGRESS_HOSTS[@]}"; do
            printf '  - "%s"\n' "$host"
        done
        if [[ ${#EGRESS_PRIVATE_HOSTS[@]} -gt 0 ]]; then
            printf '%s\n' '# Exact hosts that may resolve to private addresses.' 'trusted_domains:'
            for host in "${EGRESS_PRIVATE_HOSTS[@]}"; do
                printf '  - "%s"\n' "$host"
            done
        fi
        printf '%s\n' \
            'forward_proxy:' \
            '  enabled: true' \
            '  # The TLS ClientHello must name the CONNECT host. Without this, a' \
            '  # tunnel to an allowed CDN-hosted name reaches any co-tenant site.' \
            '  sni_verification: true' \
            '  sni_require_tls: true' \
            '  # Long model turns can stream quietly for minutes.' \
            '  idle_timeout_seconds: 900' \
            '# No effective tunnel rate limit: the default of 60 per host and minute' \
            '# answers 429 to ordinary bursts, counts tunnels rather than data, and' \
            '# Pipelock turns 0 back into 60, so a limit that is never reached is used.' \
            'fetch_proxy:' \
            '  monitoring:' \
            '    max_requests_per_minute: 1000000' \
            '# Keep /metrics and /stats off the port pi can reach.' \
            'metrics_listen: "127.0.0.1:9091"' \
            'logging:' \
            '  format: json' \
            '  output: stdout' \
            '  include_allowed: false' \
            '  include_blocked: true'
    } >"${dir}/pipelock.yaml"
}

allowlist_start() {
    local dir=${1:?allowlist_start requires a directory}
    # Host metadata uses umask 077; this secret-free file is read by the
    # sidecar's different UID after docker cp into its private volume.
    chmod 644 "${dir}/pipelock.yaml"
    # The image has no shell, and a read-only root refuses docker cp, so the
    # config goes into an anonymous volume before the container starts.
    docker create \
        --name "$EGRESS_SIDECAR" \
        --label rapunzel.egress=1 \
        --label "rapunzel.owner=${EGRESS_OWNER}" \
        --network "$EGRESS_NETWORK" \
        --label "rapunzel.run=${RUN_ID:-}" \
        --label rapunzel.role=egress \
        --network-alias "$EGRESS_PROXY_ALIAS" \
        --user 65532:65532 \
        --read-only \
        --tmpfs /tmp \
        --mount type=volume,dst=/config \
        --env PIPELOCK_HOME=/tmp/pipelock \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --pids-limit 256 \
        --memory 512m \
        "$EGRESS_PROXY_IMAGE" \
        run --config /config/pipelock.yaml --listen "0.0.0.0:${EGRESS_PROXY_PORT}" >/dev/null
    docker cp --quiet "${dir}/pipelock.yaml" "${EGRESS_SIDECAR}:/config/pipelock.yaml"
    docker network connect "$EGRESS_OUTBOUND" "$EGRESS_SIDECAR"
    docker start "$EGRESS_SIDECAR" >/dev/null
    _egress_wait /pipelock healthcheck --addr "127.0.0.1:${EGRESS_PROXY_PORT}"
}

# Render the Caddyfile and the gateway env-file into DIR.
# Reads GW_<key variable> for each GATEWAY_BUILTINS entry (GW_ANTHROPIC_API_KEY,
# ...), GW_ANTHROPIC_OAUTH, GW_CUSTOM_URL, GW_CUSTOM_KEY and GW_CUSTOM_API. Sets
# GATEWAY_PROVIDERS, GATEWAY_CUSTOM and GATEWAY_ANTHROPIC_AUTH (api-key or oauth).
gateway_configure() {
    local dir=${1:?gateway_configure requires a directory}
    local caddyfile="${dir}/Caddyfile" envfile="${dir}/gateway.env"
    local routes="" origin="" prefix="" entry id key_name key_var style

    : >"$envfile"
    chmod 600 "$envfile"

    # Secrets stay in the env-file and are read through {env.*} at request
    # time, so the rendered config itself contains none.
    for entry in "${GATEWAY_BUILTINS[@]}"; do
        read -r id key_name origin prefix style <<<"$entry"
        key_var="GW_${key_name}"
        # An API key wins over a subscription token, as in Claude Code itself.
        # The token (from `claude setup-token`) authenticates as a Bearer
        # credential; Claude Code adds the OAuth anthropic-beta value, which
        # Caddy forwards.
        if [[ "$id" == anthropic ]]; then
            if [[ -n "${!key_var:-}" ]]; then
                GATEWAY_ANTHROPIC_AUTH=api-key
            elif [[ -n "${GW_ANTHROPIC_OAUTH:-}" ]]; then
                key_var=GW_ANTHROPIC_OAUTH style=bearer
                GATEWAY_ANTHROPIC_AUTH=oauth
            fi
        fi
        [[ -n "${!key_var:-}" ]] || continue
        printf '%s=%s\n' "$key_var" "${!key_var}" >>"$envfile"
        [[ "$prefix" != - ]] || prefix=""
        routes+=$(_gateway_route "/${id}" "$origin" "$prefix" "$style" "$key_var")$'\n'
        GATEWAY_PROVIDERS+="${id},"
    done
    origin="" prefix=""
    if [[ -n "${GW_CUSTOM_URL:-}" ]]; then
        if [[ ! "$GW_CUSTOM_URL" =~ ^(https?://[^/?#@[:space:]]+)(/[^?#[:space:]]*)?$ ]]; then
            printf 'rapunzel: RAPUNZEL_API_BASE_URL is not an http(s) URL without credentials, query or fragment: %s\n' \
                "$GW_CUSTOM_URL" >&2
            return 1
        fi
        origin=${BASH_REMATCH[1]}
        prefix=${BASH_REMATCH[2]%/}
        printf 'GW_CUSTOM_KEY=%s\n' "${GW_CUSTOM_KEY:-}" >>"$envfile"
        if [[ "${GW_CUSTOM_API:-}" == anthropic-messages ]]; then
            routes+=$(_gateway_route /custom "$origin" "$prefix" x-api-key GW_CUSTOM_KEY)$'\n'
        else
            routes+=$(_gateway_route /custom "$origin" "$prefix" bearer GW_CUSTOM_KEY)$'\n'
        fi
        GATEWAY_CUSTOM=true
    fi
    GATEWAY_PROVIDERS=${GATEWAY_PROVIDERS%,}

    if [[ -z "$routes" ]]; then
        printf '%s\n' \
            "rapunzel: RAPUNZEL_EGRESS=strict needs a provider key ($(gateway_key_names | paste -sd, - | sed 's/,/, /g')) or a custom provider (RAPUNZEL_API_BASE_URL)." \
            'rapunzel: /login (subscription) credentials cannot stay outside the sandbox; use RAPUNZEL_EGRESS=allowlist with RAPUNZEL_EGRESS_LOGINS instead.' >&2
        return 1
    fi

    cat >"$caddyfile" <<EOF
{
	admin off
	auto_https off
}

:${GATEWAY_PORT} {
	handle /healthz {
		respond 204
	}
${routes}
	handle {
		respond 403
	}
}
EOF
}

# Print the key variable of every built-in gateway provider, one per line.
gateway_key_names() {
    local entry id key_name
    for entry in "${GATEWAY_BUILTINS[@]}"; do
        read -r id key_name _ <<<"$entry"
        printf '%s\n' "$key_name"
    done
}

# Print one handle_path block. Arguments: route prefix, upstream origin,
# upstream path prefix ("v1:A,B" sends /v1/* to A and the rest to B), auth
# style (x-api-key|bearer|x-goog-api-key), key variable name.
#
# Every credential header the agent could send is removed or overwritten, and
# Google's ?key= query parameter is dropped, so the agent can never put its own
# key on an allowed provider. Caddy applies deletions after sets, so a style
# deletes only the headers it does not set.
_gateway_route() {
    local route=$1 origin=$2 prefix=$3 style=$4 key=$5
    local auth
    case "$style" in
        x-api-key)
            auth=$'\t\t\theader_up -Authorization\n\t\t\theader_up -X-Goog-Api-Key\n\t\t\theader_up X-Api-Key {env.'"$key"'}'
            ;;
        x-goog-api-key)
            auth=$'\t\t\theader_up -Authorization\n\t\t\theader_up -X-Api-Key\n\t\t\theader_up X-Goog-Api-Key {env.'"$key"'}'
            ;;
        *)
            auth=$'\t\t\theader_up -X-Api-Key\n\t\t\theader_up -X-Goog-Api-Key\n\t\t\theader_up Authorization "Bearer {env.'"$key"'}"'
            ;;
    esac
    printf '\thandle_path %s/* {\n' "$route"
    printf '\t\turi query -key\n'
    if [[ "$prefix" == v1:*,* ]]; then
        prefix=${prefix#v1:}
        printf '\t\t@v1 path /v1/*\n'
        printf '\t\trewrite @v1 %s{uri}\n' "${prefix%%,*}"
        printf '\t\trewrite * %s{uri}\n' "${prefix#*,}"
    elif [[ -n "$prefix" ]]; then
        printf '\t\trewrite * %s{uri}\n' "$prefix"
    fi
    printf '\t\treverse_proxy %s {\n' "$origin"
    printf '\t\t\theader_up Host {upstream_hostport}\n'
    printf '%s\n' "$auth"
    printf '\t\t\tflush_interval -1\n'
    printf '\t\t}\n\t}\n'
}

gateway_start() {
    local dir=${1:?gateway_start requires a directory}
    # The image's caddy binary carries the NET_BIND_SERVICE file capability
    # and cannot be executed without it in the bounding set.
    # The config travels as an env value rather than a bind mount, so it works
    # without Docker Desktop file sharing and with remote Docker contexts.
    docker create \
        --name "$EGRESS_SIDECAR" \
        --label rapunzel.egress=1 \
        --label "rapunzel.owner=${EGRESS_OWNER}" \
        --network "$EGRESS_NETWORK" \
        --label "rapunzel.run=${RUN_ID:-}" \
        --label rapunzel.role=egress \
        --network-alias "$GATEWAY_ALIAS" \
        --user 65534:65534 \
        --read-only \
        --tmpfs /tmp \
        --env XDG_CONFIG_HOME=/tmp/config \
        --env XDG_DATA_HOME=/tmp/data \
        --cap-drop=ALL \
        --cap-add=NET_BIND_SERVICE \
        --security-opt=no-new-privileges \
        --pids-limit 256 \
        --memory 512m \
        --env-file "${dir}/gateway.env" \
        --env "GW_CADDYFILE=$(<"${dir}/Caddyfile")" \
        "$GATEWAY_IMAGE" \
        sh -c 'printf "%s\n" "$GW_CADDYFILE" >/tmp/Caddyfile && exec caddy run --config /tmp/Caddyfile --adapter caddyfile' \
        >/dev/null
    docker network connect "$EGRESS_OUTBOUND" "$EGRESS_SIDECAR"
    docker start "$EGRESS_SIDECAR" >/dev/null
    _egress_wait wget -q -O /dev/null "http://127.0.0.1:${GATEWAY_PORT}/healthz"
}

# Run a readiness command inside the sidecar until it succeeds.
_egress_wait() {
    local attempt
    for attempt in $(seq 1 50); do
        if docker exec "$EGRESS_SIDECAR" "$@" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    printf 'rapunzel: the egress sidecar did not become ready after %s attempts:\n' "$attempt" >&2
    docker logs --tail 20 "$EGRESS_SIDECAR" >&2 || true
    return 1
}

egress_stop() {
    if [[ -n "$EGRESS_SIDECAR" ]]; then
        # --volumes also removes the anonymous config volume.
        docker rm --force --volumes "$EGRESS_SIDECAR" >/dev/null 2>&1 || true
    fi
    local network
    for network in "$EGRESS_NETWORK" "$EGRESS_OUTBOUND"; do
        [[ -z "$network" ]] || docker network rm "$network" >/dev/null 2>&1 || true
    done
}
