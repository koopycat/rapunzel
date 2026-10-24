## MODIFIED Requirements

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

## ADDED Requirements

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
