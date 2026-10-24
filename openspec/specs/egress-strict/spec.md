# egress-strict Specification

## Purpose

In `strict` mode the provider credentials never enter the agent container. A Caddy reverse proxy on the internal network holds the real keys, forwards only fixed provider routes, and always overwrites the auth headers, so the agent can neither read the key nor use an allowed provider with a key of its own. Sources: `rapunzel`, `lib/egress.sh`, `lib/policy.sh`, `profiles/pi/bootstrap.mjs`, `profiles/opencode/bootstrap.mjs`, `profiles/claude/bootstrap.mjs`, `docs/egress.md` (D5, D6, D8, D15, D17).

## Requirements

### Requirement: Gateway routes from host keys

The gateway SHALL expose one route per built-in provider whose key is set: `/anthropic` (`ANTHROPIC_API_KEY`, `https://api.anthropic.com`), `/openai` (`OPENAI_API_KEY`, `https://api.openai.com`), `/openrouter` (`OPENROUTER_API_KEY`, `https://openrouter.ai/api`), `/google` (`GEMINI_API_KEY`, `https://generativelanguage.googleapis.com`), `/groq` (`GROQ_API_KEY`, `https://api.groq.com/openai`), `/mistral` (`MISTRAL_API_KEY`, `https://api.mistral.ai`), `/deepseek` (`DEEPSEEK_API_KEY`, `https://api.deepseek.com`), and `/xai` (`XAI_API_KEY`, `https://api.x.ai`). For a profile that allows `CLAUDE_CODE_OAUTH_TOKEN`, that token SHALL also open `/anthropic`; with both, the API key SHALL be used. `/custom` (to the custom base URL's origin, prefixed with its path) SHALL exist when a custom base URL is set. `/healthz` SHALL answer 204 and every other path 403. With no route the launcher MUST stop, name the key variables, and point users with `/login` subscriptions to allowlist mode. Caddy's admin API and automatic HTTPS SHALL be off.

#### Scenario: Unknown route
- **WHEN** the agent requests `http://llm-proxy:8080/anything`
- **THEN** the gateway answers 403

#### Scenario: No keys
- **WHEN** strict mode runs without any built-in provider key or a custom base URL
- **THEN** the launcher exits, lists the key variables it accepts, and recommends `RAPUNZEL_EGRESS=allowlist` with `RAPUNZEL_EGRESS_LOGINS`

#### Scenario: Further provider key
- **WHEN** strict mode runs with only `GEMINI_API_KEY` set
- **THEN** the gateway exposes `/google` and no other provider route

#### Scenario: OpenRouter base URLs
- **WHEN** the agent sends requests to `/openrouter/v1/messages` and to `/openrouter/chat/completions`
- **THEN** the upstream receives them at `/api/v1/messages` and `/api/v1/chat/completions`

#### Scenario: Subscription token for Claude Code
- **WHEN** strict mode runs the claude profile with only `CLAUDE_CODE_OAUTH_TOKEN` set
- **THEN** the gateway exposes `/anthropic` and authenticates upstream with that token

#### Scenario: Subscription token for pi
- **WHEN** strict mode runs the pi profile with only `CLAUDE_CODE_OAUTH_TOKEN` set
- **THEN** the token is not forwarded and the launcher stops because there is no route

### Requirement: Auth headers always overwritten

Each route SHALL remove every credential header it does not set and set its own from the real credential: `X-Api-Key` for an Anthropic API key and for a custom provider with `RAPUNZEL_API=anthropic-messages`, `X-Goog-Api-Key` for Google, `Authorization: Bearer` for an Anthropic subscription token and otherwise. Every route SHALL drop a `key` query parameter. The gateway MUST overwrite rather than swap a placeholder, set `Host` to the upstream, verify upstream TLS, forward `anthropic-*` request headers unchanged, and stream responses without buffering.

#### Scenario: Agent supplies its own key
- **WHEN** the agent sends a request to `/openai` with `Authorization: Bearer sk-attacker`
- **THEN** the upstream receives the user's key, not the attacker's

#### Scenario: Agent adds an API key to a subscription route
- **WHEN** the `/anthropic` route uses a subscription token and the agent sends `X-Api-Key: sk-attacker`
- **THEN** the upstream receives no `X-Api-Key` and the user's token as `Authorization: Bearer`

#### Scenario: Agent puts its own key in the query
- **WHEN** the agent requests `/google/v1beta/models?key=attacker`
- **THEN** the upstream receives no `key` parameter and the user's key as `X-Goog-Api-Key`

### Requirement: Keys never enter the agent

The real keys and the upstream URL SHALL be passed only to the gateway container, through a mode-0600 env file, and Caddy reads them through `{env.*}` at request time, so the rendered Caddyfile contains no secret. Of the provider settings, the agent SHALL receive only the profile's gateway-allowed names, `RAPUNZEL_GATEWAY_URL=http://llm-proxy:8080`, `RAPUNZEL_GATEWAY_PROVIDERS`, `RAPUNZEL_GATEWAY_ANTHROPIC_AUTH` (`api-key` or `oauth`) when the Anthropic route exists, and, for a custom provider, `RAPUNZEL_API_BASE_URL=<gateway>/custom` with the placeholder key `rapunzel-gateway` in `RAPUNZEL_API_KEY` and in any named key variable. `CLAUDE_CODE_OAUTH_TOKEN` from the host MUST NOT reach the agent in strict mode.

#### Scenario: Agent searches for the key
- **WHEN** the agent dumps its environment and files
- **THEN** it finds only the placeholder `rapunzel-gateway`, never the real key

#### Scenario: Extension provider in strict mode
- **WHEN** `RAPUNZEL_API_BASE_URL` is set, `RAPUNZEL_API_KEY_VARIABLE=OMNIROUTE_API_KEY`, and `RAPUNZEL_BASE_URL_VARIABLE=OMNIROUTE_BASE_URL`
- **THEN** the agent receives `OMNIROUTE_API_KEY=rapunzel-gateway` and `OMNIROUTE_BASE_URL=http://llm-proxy:8080/custom`

#### Scenario: Subscription token stays on the host
- **WHEN** Claude Code runs in strict mode with `CLAUDE_CODE_OAUTH_TOKEN` in `claude.env`
- **THEN** the agent's environment and files contain only the placeholder in place of the token

### Requirement: Harness points at the gateway

In strict mode, a harness that supports it SHALL be configured by its bootstrap to use the gateway routes with the placeholder key for every provider the gateway serves. Harnesses whose profiles do not declare strict support are refused (see `harness-profiles`).

#### Scenario: pi with an Anthropic key
- **WHEN** pi starts in strict mode with `ANTHROPIC_API_KEY` set on the host
- **THEN** pi's `anthropic` provider uses `http://llm-proxy:8080/anthropic` with key `rapunzel-gateway`

#### Scenario: Claude Code with an API key
- **WHEN** Claude Code starts in strict mode with `ANTHROPIC_API_KEY` set on the host
- **THEN** the `env` block of its `settings.json` sets `ANTHROPIC_BASE_URL=http://llm-proxy:8080/anthropic` and `ANTHROPIC_AUTH_TOKEN=rapunzel-gateway`, and its WebFetch preflight is off

#### Scenario: Claude Code with a subscription token
- **WHEN** Claude Code starts in strict mode with only `CLAUDE_CODE_OAUTH_TOKEN` set on the host
- **THEN** the `env` block sets `ANTHROPIC_BASE_URL=http://llm-proxy:8080/anthropic` and `CLAUDE_CODE_OAUTH_TOKEN=rapunzel-gateway`

#### Scenario: Claude Code back in allowlist mode
- **WHEN** Claude Code starts in allowlist mode after a strict run
- **THEN** the bootstrap has removed the gateway entries it wrote and leaves the user's own `env` entries alone

### Requirement: OAuth logins cannot be protected

Strict mode MUST NOT accept `RAPUNZEL_EGRESS_LOGINS`, and the bootstraps SHALL warn when the state volume still holds `/login` credentials, because the harness refreshes those tokens itself inside the sandbox. A host-issued token passed as an environment variable, such as `CLAUDE_CODE_OAUTH_TOKEN`, is not a `/login` credential.

#### Scenario: Leftover login
- **WHEN** pi starts in strict mode and `auth.json` contains a provider login
- **THEN** pi prints a warning to run `/logout` for each provider

#### Scenario: Leftover Claude Code login
- **WHEN** Claude Code starts in strict mode and its state directory holds `.credentials.json`
- **THEN** the bootstrap prints a warning to run `/logout`

### Requirement: Tool allowlist next to the gateway

In strict mode, `RAPUNZEL_EGRESS_ALLOW` SHALL start Pipelock next to the gateway with the `allowlist` configuration and give the agent `HTTPS_PROXY`, `https_proxy`, and `NODE_USE_ENV_PROXY=1` for it, plus `NO_PROXY=llm-proxy`, so model traffic stays plain HTTP to the gateway. `HTTP_PROXY` MUST stay unset. Without `RAPUNZEL_EGRESS_ALLOW`, strict mode SHALL start no proxy.

#### Scenario: Package install in strict mode
- **WHEN** strict mode runs with `RAPUNZEL_EGRESS_ALLOW=registry.npmjs.org`
- **THEN** the agent reaches `registry.npmjs.org` over HTTPS, its model requests still carry only the placeholder, and the gateway sends the real key upstream

#### Scenario: Host not on the tool allowlist
- **WHEN** the agent connects to a host that is not in `RAPUNZEL_EGRESS_ALLOW`
- **THEN** the proxy refuses the tunnel

### Requirement: Provider hosts stay behind the gateway

In strict mode the launcher MUST stop before creating networks, sidecars, or the agent when a `RAPUNZEL_EGRESS_ALLOW` entry equals a built-in provider's API host or the custom provider's host, or is a `*.` wildcard that covers one, because the agent could reach that provider with a key of its own. `rapunzel --config` SHALL stop on the same entry.

#### Scenario: Wildcard covers a provider
- **WHEN** strict mode runs with `RAPUNZEL_EGRESS_ALLOW='*.anthropic.com'`
- **THEN** the launcher exits and names the entry and the provider host it covers

#### Scenario: Custom provider host
- **WHEN** strict mode runs with `RAPUNZEL_API_BASE_URL=https://llm.example.com/v1` and `RAPUNZEL_EGRESS_ALLOW=llm.example.com`
- **THEN** the launcher exits before creating the egress networks
