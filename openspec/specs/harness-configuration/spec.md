# harness-configuration Specification

## Purpose

On every container start, the entrypoint runs the harness's bootstrap script, which turns host-side provider settings (`RAPUNZEL_*` and keys) into the harness's own configuration inside the state volume. Launcher-managed entries are rewritten each time, so edits the agent makes to them do not persist. Sources: `bootstrap.sh`, `rapunzel-shell`, `profiles/<name>/bootstrap.mjs`, `profiles/dsh/web.patch.yml`.

## Requirements

### Requirement: Entrypoint order

The entrypoint SHALL require `RAPUNZEL_STATE_DIR`, create it, set up the identity, run `/usr/local/lib/rapunzel/bootstrap-harness.mjs` with the state directory when the image ships one, and then exec the requested command. The `--shell` entrypoint SHALL run the same steps before starting an interactive bash. A bootstrap failure MUST stop the start.

#### Scenario: Invalid numeric setting
- **WHEN** pi starts with a custom provider configured and `RAPUNZEL_CONTEXT_WINDOW=abc`
- **THEN** the bootstrap fails with a message naming the variable and the harness does not start

### Requirement: pi custom provider

When `RAPUNZEL_PROVIDER`, a base URL (`RAPUNZEL_API_BASE_URL` or `RAPUNZEL_BASE_URL`), and a model (`RAPUNZEL_MODEL` or `RAPUNZEL_MODEL_ID`) are all set, the pi bootstrap SHALL merge a provider into `models.json` with that base URL, `RAPUNZEL_API` (default `openai-completions`), the key as a `$<RAPUNZEL_API_KEY_VARIABLE>` reference (default `RAPUNZEL_API_KEY`), and one model. The key value MUST NOT be written to `models.json`.

#### Scenario: Provider registered
- **WHEN** pi starts with `RAPUNZEL_PROVIDER=router`, `RAPUNZEL_API_BASE_URL=https://r.example/v1`, `RAPUNZEL_MODEL=m1`
- **THEN** `models.json` has `providers.router` with `apiKey: "$RAPUNZEL_API_KEY"` and model `m1`, and `settings.json` defaults to `router/m1` unless the user already chose a default

### Requirement: pi custom provider options

The model SHALL take `RAPUNZEL_MODEL_NAME`, `RAPUNZEL_REASONING`, `RAPUNZEL_CONTEXT_WINDOW` (default 128000), and `RAPUNZEL_MAX_TOKENS` (default 16384); the provider SHALL take `RAPUNZEL_COMPAT_JSON`, `RAPUNZEL_HEADERS_JSON`, and `RAPUNZEL_AUTH_HEADER`. When the custom provider is configured, invalid JSON or non-positive numbers MUST stop the start; without one, these settings are ignored.

#### Scenario: Reasoning model
- **WHEN** `RAPUNZEL_REASONING=true` and `RAPUNZEL_CONTEXT_WINDOW=200000`
- **THEN** the model entry has `reasoning: true` and `contextWindow: 200000`

#### Scenario: Credential in custom headers
- **WHEN** `RAPUNZEL_HEADERS_JSON` contains an `Authorization` header or a `Bearer` value
- **THEN** the bootstrap warns that the credential is stored in plaintext in `models.json` (mode 0600) in the volume

### Requirement: pi gateway overrides

In strict mode the pi bootstrap SHALL point each built-in provider listed in `RAPUNZEL_GATEWAY_PROVIDERS` at the gateway (`/anthropic`, `/openai/v1`) with the placeholder key `rapunzel-gateway`. In other modes it MUST remove such overrides left by an earlier strict run. When `auth.json` holds `/login` credentials in strict mode, it SHALL warn that the gateway cannot keep them out.

#### Scenario: Switching from strict back to open
- **WHEN** a project last ran in strict mode and now runs in open mode
- **THEN** the `anthropic` and `openai` entries no longer carry the gateway base URL or placeholder key

### Requirement: pi settings defaults

The pi bootstrap SHALL create `sessions`, `extensions`, `skills`, `prompts`, and `themes` in the state directory, and default `defaultProjectTrust` to `ask`, `enableAnalytics` to `false`, and `quietStartup` to `false` without overriding user values. `sessionDir` MUST be an absolute path in the state directory; a missing or relative value is replaced, because pi resolves relative paths from `/workspace`, which would put sessions on the host. `models.json` and `settings.json` MUST be mode 0600.

#### Scenario: Relative session directory repaired
- **WHEN** `settings.json` has `sessionDir: "sessions"`
- **THEN** the bootstrap rewrites it to `/home/agent/.pi/agent/sessions`

### Requirement: Claude Code onboarding

When `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` is set, the Claude Code bootstrap SHALL mark onboarding complete in `.claude.json` so the host credential is used without a login prompt. Without a credential it MUST leave onboarding alone so `/login` stays reachable.

#### Scenario: Setup token from the host
- **WHEN** Claude Code starts with `CLAUDE_CODE_OAUTH_TOKEN` set and a fresh volume
- **THEN** `.claude.json` has `hasCompletedOnboarding: true` and the token is not written to the volume

### Requirement: Codex defaults

The Codex bootstrap SHALL prepend missing top-level defaults to `config.toml`: `sandbox_mode = "danger-full-access"` (bubblewrap cannot run in the container; rapunzel is the boundary and approval prompts stay on), `cli_auth_credentials_store = "file"`, `check_for_update_on_startup = false`, and analytics disabled. Keys the user already set at the top level, or an existing `[analytics]` table, MUST win.

#### Scenario: User override kept
- **WHEN** `config.toml` already sets `sandbox_mode = "read-only"` at the top level
- **THEN** the bootstrap leaves that value and adds only the other missing keys

### Requirement: dsh session-log upload off

The dsh bootstrap SHALL seed `cordis.patch.yml` once, disabling session-log upload to the official DeepSeek API. It MUST NOT overwrite an existing file, so the user can remove the row to turn uploads back on.

#### Scenario: Existing patch kept
- **WHEN** `cordis.patch.yml` already exists
- **THEN** the bootstrap leaves it unchanged

### Requirement: opencode provider file

The opencode bootstrap SHALL write a rapunzel-owned `rapunzel/opencode.json`, loaded through `OPENCODE_CONFIG`, from the environment alone on every start. The user's own `opencode.json` MUST NOT be edited.

#### Scenario: Provider removed from the env file
- **WHEN** a previous start configured a custom provider and the env file no longer sets one
- **THEN** the rewritten provider file contains no provider

### Requirement: opencode custom provider

When a custom base URL is set, the opencode bootstrap SHALL configure a custom provider (id `RAPUNZEL_PROVIDER`, default `custom`) from the pi `RAPUNZEL_*` settings, only for `RAPUNZEL_API=openai-completions`, with the key as an `{env:...}` reference and with models listed from the endpoint's `/models` (5-second timeout, at most 1000 entries). When `RAPUNZEL_MODEL` is set, it SHALL become opencode's default model.

#### Scenario: Unsupported API style
- **WHEN** `RAPUNZEL_API=anthropic-messages` is set for opencode
- **THEN** the bootstrap warns and configures no custom provider

### Requirement: opencode model cache fallback

When model listing fails, the opencode bootstrap SHALL fall back to its cache for the same base URL, sanitized to the fields a listing can produce because the cache is agent-writable, and otherwise offer only the configured model.

#### Scenario: Router unreachable in allowlist mode
- **WHEN** model listing fails behind the proxy and a cache for the same URL exists
- **THEN** opencode gets the cached models and a warning that mentions `RAPUNZEL_EGRESS_ALLOW_PRIVATE` for private hosts

### Requirement: opencode gateway providers

In strict mode the opencode bootstrap SHALL point the built-in `anthropic` and `openai` providers the gateway serves at `/anthropic/v1` and `/openai/v1` with the placeholder key, and SHALL warn when `auth.json` in the volume holds logins.

#### Scenario: OpenAI key in strict mode
- **WHEN** opencode starts in strict mode with `OPENAI_API_KEY` set on the host
- **THEN** the provider file sets `openai` to `http://llm-proxy:8080/openai/v1` with key `rapunzel-gateway`
