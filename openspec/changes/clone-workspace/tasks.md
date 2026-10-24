# Tasks

## 1. Mode selection

- [x] 1.1 Parse `--clone` (after `--harness`, before the run mode) and `RAPUNZEL_WORKSPACE=mount|clone` in `rapunzel`, refuse other values with status 2, and require a git repository with a commit in clone mode before any Docker call; add `--fetch [PROJECT_DIR]`; verify with 1.3
- [x] 1.2 Add the workspace volume name to `lib/volumes.sh` (`rapunzel-<harness>-<hash>-workspace`) with the same ownership preparation, and `workspace` / `workspaceVolume` to the config report; verify with 1.3
- [x] 1.3 Extend `test-control.sh`: invalid `RAPUNZEL_WORKSPACE` exits 2, clone mode outside a repository fails without Docker, the report shows the workspace mode and volume; run `./test-control.sh` and verify PASS

## 2. Bundles and helper

- [x] 2.1 Create `lib/workspace.sh` with the helper container invocation (networkless, no capabilities, caller UID, only the workspace volume) and `workspace_seed` (first clone with author config and branch checkout, later fetch into `refs/remotes/origin/*`, incremental exclusions); verify with 2.4
- [x] 2.2 Add `workspace_fetch` (bundle to stdout, host `git fetch` with `transfer.fsckObjects`, `--no-tags`, `--no-write-fetch-head`, refspec `+refs/heads/*:refs/remotes/rapunzel-<harness>/*`) and `workspace_report` (new commits per branch, host-executed paths touched, uncommitted work); verify with 2.4
- [x] 2.3 Wire clone mode into `rapunzel`: mount the workspace volume at `/workspace`, skip `host_files_mounts` and the snapshot, seed before the run, fetch and report in cleanup after the agent exits; make `--fetch` run only the fetch and report; verify with 2.4
- [x] 2.4 Write `verify-workspace.sh`: clone-mode agent sees no host-path mount; agent commit appears at `refs/remotes/rapunzel-pi/<branch>`; host branch unchanged; a host commit appears in the next run's `origin/<branch>` without moving the agent branch; workspace hook, `core.fsmonitor`, and tag never reach the host; a commit adding `.envrc` is reported; uncommitted work is reported; `--fetch` works without starting pi; run `./verify-workspace.sh` and verify PASS

## 3. Documentation and CI

- [x] 3.1 Document clone mode in `docs/guide.md` (usage, what is not copied, reviewing and merging, resetting the volume), `README.md`, `docs/architecture.md` (new section, threat model, limitations), and the `AGENTS.md` invariant on host bind mounts; verify the documented commands run as written
- [x] 3.2 Add `verify-workspace.sh` to `ci.yml`, to ShellCheck there, and to `AGENTS.md` commands; verify `actionlint` or a dry read of the workflow shows the step after the host-file check

## 4. Integration

- [x] 4.1 Run ShellCheck, `./test-control.sh`, `./test.sh`, `./verify-isolation.sh .`, `./verify-host-files.sh`, and `./verify-workspace.sh` on Colima, and verify all pass
