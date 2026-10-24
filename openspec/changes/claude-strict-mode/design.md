# Design

## Context

Strict mode today (`lib/egress.sh` `gateway_configure`, D5/D6/D8 in `docs/egress.md`): the launcher renders a Caddyfile whose routes overwrite the auth header with a key read from the gateway's env file, and passes the agent `RAPUNZEL_GATEWAY_URL` and `RAPUNZEL_GATEWAY_PROVIDERS`. Each strict-capable bootstrap (pi, opencode) rewrites its own config from those two variables and removes its overrides again when they are absent.
Claude Code's gateway contract is documented at code.claude.com/docs/en/llm-gateway-connect and llm-gateway-protocol: `ANTHROPIC_BASE_URL`, a credential in `ANTHROPIC_AUTH_TOKEN` (sent as `Authorization: Bearer`) or `ANTHROPIC_API_KEY` (sent as `X-Api-Key`, needs a one-time interactive approval), and `anthropic-*` headers forwarded unchanged. With a subscription login and only `ANTHROPIC_BASE_URL`, Claude Code keeps authenticating with OAuth and adds an OAuth value to `anthropic-beta`.

## Goals / Non-Goals

**Goals:**
- Claude Code in strict mode with an Anthropic API key, with the same guarantees as pi.
- The same for a `claude setup-token` subscription token, if Claude Code accepts a placeholder token.

**Non-Goals:**
- Codex and dsh strict mode.
- Protecting a `/login` session stored in the volume; that stays an allowlist-mode feature.
- Fast mode, which checks availability against `api.anthropic.com` directly.

## Decisions

**Configure Claude Code through `settings.json`, not launcher env.**
The `env` block of `$CLAUDE_CONFIG_DIR/settings.json` takes precedence over the process environment, so an agent that once wrote its own `ANTHROPIC_BASE_URL` there would override anything the launcher passes. Writing the block from the bootstrap on every start, as pi rewrites `models.json`, keeps one mechanism for all strict harnesses and wins over leftovers. The bootstrap removes only entries whose values are the gateway's own, so user entries survive mode changes.
Alternative: `--env ANTHROPIC_BASE_URL=...` from the launcher. Rejected because of that precedence.

**API-key placeholder in `ANTHROPIC_AUTH_TOKEN`.**
`ANTHROPIC_API_KEY` needs an interactive approval the first time and is ignored silently once declined. `ANTHROPIC_AUTH_TOKEN` takes effect immediately and arrives as `Authorization: Bearer`, which the existing x-api-key route already strips before setting `X-Api-Key`.

**Subscription token: Bearer route, placeholder in `CLAUDE_CODE_OAUTH_TOKEN`.**
Claude Code then stays in OAuth mode and sends the OAuth `anthropic-beta` value, which Caddy forwards; the route removes `X-Api-Key` and sets `Authorization: Bearer {env.GW_ANTHROPIC_OAUTH}`. `RAPUNZEL_GATEWAY_ANTHROPIC_AUTH=api-key|oauth` tells the bootstrap which variable holds the placeholder.
The open point is whether Claude Code validates the token locally or calls an Anthropic endpoint outside `ANTHROPIC_BASE_URL` before the first request. Task 3.2 checks it live; if it fails, the launcher refuses strict mode with only a subscription token, with a message pointing to an API key or allowlist mode, and the specs' subscription scenarios are dropped before archive.

**Only profiles that allow the variable can feed the route.**
`CLAUDE_CODE_OAUTH_TOKEN` is in the claude profile's `H_ENV_ALLOW`; the launcher adds it to the gateway-consumed names only when the active profile allows it, so pi never forwards it anywhere.

**WebFetch preflight off in strict mode.**
The preflight calls `api.anthropic.com` directly and has no route, so every WebFetch would fail on the preflight. The bootstrap sets `skipWebFetchPreflight: true` in strict mode and removes it otherwise; WebFetch itself has no route in strict mode either, so nothing is weakened.

**Test the routes offline, the harness live.**
The `/anthropic` upstream is fixed, so the offline suite checks the rendered Caddyfile for both credential kinds in `test-control.sh`, and `verify-egress.sh` checks the agent side: settings, placeholder, no real credential anywhere in the container. One live check with a real credential confirms Claude Code answers through the gateway.

## Risks / Trade-offs

- [Claude Code adds a startup call outside the base URL] → It fails closed (no route); the live check catches it before release, and the Renovate harness PR is reviewed by hand.
- [A future Claude Code release stops honoring the `env` block for these variables] → `verify-egress.sh` checks what Claude Code reports through `/status`-equivalent output only indirectly; the live check in the release review catches it.
- [Subscription usage through a gateway] → Documented by Anthropic as supported; plan limits still apply because Claude Code authenticates with OAuth.
