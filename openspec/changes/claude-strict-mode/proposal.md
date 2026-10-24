# Proposal

## Why

Claude Code is the most widely used harness rapunzel runs, and it is limited to `open` and `allowlist`, so the agent always holds a real Anthropic credential that a prompt injection can send to any allowed host.
Claude Code now documents LLM gateways officially: `ANTHROPIC_BASE_URL` plus a gateway credential variable, with `anthropic-*` headers forwarded unchanged, including subscription logins whose OAuth `anthropic-beta` value the gateway must pass through.
`docs/architecture.md` still says Claude Code "is not yet known to accept" this.

## What Changes

- The `claude` profile declares strict support. In strict mode its bootstrap points Claude Code at `http://llm-proxy:8080/anthropic` with the placeholder `rapunzel-gateway`, through the `env` block of the volume's `settings.json`, and removes those entries again in other modes.
- The gateway's `/anthropic` route can also be fed by `CLAUDE_CODE_OAUTH_TOKEN` (from the host's `claude setup-token`) for profiles that allow that variable. Then it sets `Authorization: Bearer <token>` and removes `X-Api-Key`; with `ANTHROPIC_API_KEY` set the API key wins, as in Claude Code itself.
- The agent's placeholder sits in the variable matching the credential kind: `ANTHROPIC_AUTH_TOKEN` for an API key, `CLAUDE_CODE_OAUTH_TOKEN` for a subscription token.
- In strict mode the bootstrap turns off Claude Code's WebFetch domain preflight, which calls `api.anthropic.com` directly and has no route, and warns when the volume still holds a `/login` credential file.
- If the live check shows that Claude Code rejects a placeholder OAuth token, the launcher instead refuses strict mode with only `CLAUDE_CODE_OAUTH_TOKEN` and explains why; the API-key path ships either way.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `egress-strict`: the Anthropic route accepts a subscription token, the placeholder variable depends on the credential kind, and Claude Code is a harness the bootstrap points at the gateway.
- `harness-profiles`: claude supports strict mode; codex and dsh still do not.

## Impact

- `profiles/claude/profile.sh`, `profiles/claude/bootstrap.mjs`, `rapunzel` (gateway-consumed names), `lib/egress.sh` (`gateway_configure`).
- `verify-egress.sh` (new `check_strict_claude`), `test-control.sh` (rendered Caddyfile for both credential kinds).
- `docs/guide.md`, `docs/architecture.md`, `docs/egress.md` (new decision record), `README.md` (Claude Code section).
- Strict mode bills API-key traffic per token as before; a subscription token keeps its plan limits, since Claude Code still authenticates with OAuth.
