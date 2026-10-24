# Tasks

## 1. Agent resource limits

- [x] 1.1 In `rapunzel`, read and validate `RAPUNZEL_PIDS_LIMIT` (default 4096, integer ≥ 64) and `RAPUNZEL_MEMORY` (unset, or `^[0-9]+[bkmgBKMG]?$` ≥ 64 MiB) before any Docker call, and add `--pids-limit` and, when set, `--memory` to the agent's `docker run`; verify an invalid value exits non-zero without contacting Docker (covered in 1.3)
- [x] 1.2 Add `limits: {pids, memory}` to `config_report` in `lib/policy.sh` and a `Limits:` line to the text view in `lib/ctl-output.jq`; verify with `./test-control.sh`
- [x] 1.3 Extend `test-control.sh`: default report shows `pids == 4096` and `memory == null`; custom values are reported; `RAPUNZEL_PIDS_LIMIT=unlimited`, `RAPUNZEL_PIDS_LIMIT=10`, `RAPUNZEL_MEMORY=lots`, and `RAPUNZEL_MEMORY=1m` all fail; run `./test-control.sh` and verify PASS
- [x] 1.4 Extend `verify-isolation.sh` / `verify-isolation-inner.sh` to check `/sys/fs/cgroup/pids.max` is 4096 and `memory.max` is `max` by default, and the custom values with `RAPUNZEL_PIDS_LIMIT=512 RAPUNZEL_MEMORY=256m`; run `./verify-isolation.sh .` and verify it passes
- [x] 1.5 Document `RAPUNZEL_PIDS_LIMIT` and `RAPUNZEL_MEMORY` in `docs/guide.md` (configuration and troubleshooting for `fork: Resource temporarily unavailable`), `docs/architecture.md` (4.1 and Appendix A), the launcher's usage text, and the `AGENTS.md` invariants if they list run flags; verify `./rapunzel --help` shows both

## 2. Host-executed paths

- [x] 2.1 Add `.pi .agents .claude/commands .claude/agents .claude/skills .claude/hooks .cargo/config.toml .cargo/config build.rs .idea/runConfigurations .run` to `HOST_EXECUTED_PATHS` in `lib/host-files.sh`; verify with 2.2
- [x] 2.2 Extend `verify-host-files.sh` to plant `.pi/extensions/evil.ts`, `build.rs`, and `.claude/commands/x.md` and expect `added:` lines for each; run `./verify-host-files.sh` and verify PASS
- [x] 2.3 Update the path list in `docs/guide.md` and `docs/architecture.md` 4.6, and note that nested `build.rs` and `.idea/workspace.xml` are not watched; verify the docs name every new path

## 3. Documentation fix

- [x] 3.1 Replace "currently pinned 3.6.0" in `docs/egress.md` (D14) with a pointer to the pin in `lib/egress.sh`, keeping the 3.5.0 test record; verify `grep -n 'currently pinned' docs/egress.md` returns nothing

## 4. Allowlist rate limit

- [x] 4.1 Render `fetch_proxy.monitoring.max_requests_per_minute: 1000000` in `allowlist_configure` (`lib/egress.sh`) with a comment on why 0 does not work; verify with 4.2
- [x] 4.2 Assert the rendered key in `test-control.sh`, and add a probe check to `lib/egress-probe.mjs` that opens 70 tunnels to the allowed host and requires no `429`, with the allowlist check counts in `verify-egress.sh` raised by one; run `./test-control.sh` and `./verify-egress.sh allowlist` and verify PASS
- [x] 4.3 Record the setting in `docs/egress.md` (D4) and the guide's allowlist section; verify both mention the limit and why

- [x] 4.4 Move the fault-injection shim in `verify-control.sh` out of the agent-mounted project, because Colima's inotify forwarding can revert its `chmod +x` and make the shim silently unused; verify five consecutive `./verify-control.sh` runs pass after `./verify-egress.sh`

## 5. Integration

- [x] 5.1 Run ShellCheck on changed scripts, `./test-control.sh`, `./test.sh`, `./verify-isolation.sh .`, `./verify-host-files.sh`, `./verify-egress.sh`, and `./verify-control.sh` on Colima, and verify all pass
