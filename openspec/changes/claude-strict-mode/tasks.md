# Tasks

## 1. Gateway

- [x] 1.1 In `lib/egress.sh`, accept `GW_ANTHROPIC_OAUTH`: when `GW_ANTHROPIC_KEY` is empty and the token is set, render `/anthropic` with the bearer style and `GW_ANTHROPIC_OAUTH`; set `GATEWAY_ANTHROPIC_AUTH=api-key|oauth`; verify with 1.3
- [x] 1.2 In `rapunzel`, read `CLAUDE_CODE_OAUTH_TOKEN` into `GW_ANTHROPIC_OAUTH` and add it to the gateway-consumed names only when the profile allows it, and pass `RAPUNZEL_GATEWAY_ANTHROPIC_AUTH` to the agent; verify `rapunzel-ctl config` in strict mode reports the token as present and `providerKeysEnterAgent` false
- [x] 1.3 Extend `test-control.sh` to render the gateway config for an API key, a subscription token, and both, and assert the header lines (`-Authorization` + `X-Api-Key` vs `-X-Api-Key` + `Authorization "Bearer {env.GW_ANTHROPIC_OAUTH}"`) and that no secret value appears in the Caddyfile; run `./test-control.sh` and verify PASS

## 2. Claude profile and bootstrap

- [x] 2.1 Set `H_STRICT_SUPPORTED=true` and `H_ENV_ALLOW_GATEWAY=(ANTHROPIC_MODEL)` in `profiles/claude/profile.sh`; verify `RAPUNZEL_EGRESS=strict ./rapunzel-ctl config . --harness claude` succeeds with a key and `RAPUNZEL_EGRESS=strict` for codex still exits 2
- [x] 2.2 In `profiles/claude/bootstrap.mjs`, when `RAPUNZEL_GATEWAY_URL` is set and the providers include `anthropic`, write `env.ANTHROPIC_BASE_URL` and the placeholder variable chosen by `RAPUNZEL_GATEWAY_ANTHROPIC_AUTH` plus `skipWebFetchPreflight: true` into `settings.json`; otherwise remove exactly those entries when they carry the gateway values; keep onboarding marked done when the gateway is in use; warn when `.credentials.json` exists; verify with 2.3
- [x] 2.3 Add `check_strict_claude` to `verify-egress.sh` (runs when `rapunzel:claude` exists, like the opencode check): with a fake `ANTHROPIC_API_KEY` and with a fake `CLAUDE_CODE_OAUTH_TOKEN`, the agent's `settings.json` has the gateway URL and placeholder, the fake credentials appear nowhere in the container's environment or state directory, and a following allowlist run has the entries removed; run `./verify-egress.sh strict` and verify PASS

## 3. Live check and documentation

- [x] 3.1 Update `docs/guide.md` (Claude Code section and egress table), `README.md` (Claude Code section), `docs/architecture.md` (4.5 and section 8), and add a decision record to `docs/egress.md` for routing Claude Code through the gateway; verify no doc says Claude Code lacks strict support
- [x] 3.2 Live check with a real credential: `RAPUNZEL_EGRESS=strict ./rapunzel-claude --exec . claude -p 'reply with ok'` once with the subscription token from `~/.config/rapunzel/claude.env` and, if available, once with an API key; verify a reply arrives. If the subscription run fails because of the placeholder, implement the refusal described in design.md, drop the subscription scenarios from the delta specs, and record the result in the decision record

## 4. Integration

- [x] 4.1 Run ShellCheck, `./test-control.sh`, `./test.sh` with `RAPUNZEL_HARNESS=claude`, and `./verify-egress.sh` on Colima, and verify all pass
