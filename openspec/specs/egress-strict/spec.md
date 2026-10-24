# egress-strict Specification

## Purpose

In `strict` mode the provider credentials never enter the agent container. A Caddy reverse proxy on the internal network holds the real keys, forwards only fixed provider routes, and always overwrites the auth headers, so the agent can neither read the key nor use an allowed provider with a key of its own. Sources: `rapunzel`, `lib/egress.sh`, `profiles/pi/bootstrap.mjs`, `profiles/opencode/bootstrap.mjs`, `docs/egress.md` (D5, D6, D8).

## Requirements

### Requirement: Gateway routes from host keys

The gateway SHALL expose `/anthropic` (to `https://api.anthropic.com`) when `ANTHROPIC_API_KEY` is set, or, for a profile that allows `CLAUDE_CODE_OAUTH_TOKEN`, when that token is set; with both, the API key SHALL be used. It SHALL expose `/openai` (to `https://api.openai.com`) when `OPENAI_API_KEY` is set, and `/custom` (to the custom base URL's origin, prefixed with its path) when a custom base URL is set. `/healthz` SHALL answer 204 and every other path 403. With no route the launcher MUST stop and point users with `/login` subscriptions to allowlist mode. Caddy's admin API and automatic HTTPS SHALL be off.

#### Scenario: Unknown route
- **WHEN** the agent requests `http://llm-proxy:8080/anything`
- **THEN** the gateway answers 403

#### Scenario: No keys
- **WHEN** strict mode runs without `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or a custom base URL
- **THEN** the launcher exits and recommends `RAPUNZEL_EGRESS=allowlist` with `RAPUNZEL_EGRESS_LOGINS`

#### Scenario: Subscription token for Claude Code
- **WHEN** strict mode runs the claude profile with only `CLAUDE_CODE_OAUTH_TOKEN` set
- **THEN** the gateway exposes `/anthropic` and authenticates upstream with that token

#### Scenario: Subscription token for pi
- **WHEN** strict mode runs the pi profile with only `CLAUDE_CODE_OAUTH_TOKEN` set
- **THEN** the token is not forwarded and the launcher stops because there is no route

### Requirement: Auth headers always overwritten

Each route SHALL remove the other auth header and set its own from the real credential: `X-Api-Key` for an Anthropic API key and for a custom provider with `RAPUNZEL_API=anthropic-messages`, `Authorization: Bearer` for an Anthropic subscription token and otherwise. The gateway MUST overwrite rather than swap a placeholder, set `Host` to the upstream, verify upstream TLS, forward `anthropic-*` request headers unchanged, and stream responses without buffering.

#### Scenario: Agent supplies its own key
- **WHEN** the agent sends a request to `/openai` with `Authorization: Bearer sk-attacker`
- **THEN** the upstream receives the user's key, not the attacker's

#### Scenario: Agent adds an API key to a subscription route
- **WHEN** the `/anthropic` route uses a subscription token and the agent sends `X-Api-Key: sk-attacker`
- **THEN** the upstream receives no `X-Api-Key` and the user's token as `Authorization: Bearer`

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
