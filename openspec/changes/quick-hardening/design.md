# Design

## Context

The sidecars and the controller's validator already run with `--memory 512m --pids-limit 256` (`lib/egress.sh`, `lib/control.sh`); the agent container has neither.
Host-file snapshots walk a fixed list of relative paths (`HOST_EXECUTED_PATHS` in `lib/host-files.sh`), so coverage is exactly that list.

## Goals / Non-Goals

**Goals:**
- Stop a runaway process count in the agent from taking down the Docker VM, without breaking normal builds.
- Let users cap memory when they want to, with the same validation style as other launcher settings.
- Cover the host-executed paths the comparison found missing.

**Non-Goals:**
- CPU limits or I/O limits.
- Finding `build.rs` or run configurations in nested directories; the snapshot stays a fixed path list.
- Blocking writes to the new paths; they are reported like the rest.

## Decisions

**Process limit on by default, 4096.**
Large `cargo build -j`, `pnpm install`, or test runners stay well under a few hundred processes, so 4096 leaves headroom while a fork bomb still hits the ceiling within milliseconds.
Alternative: off by default like memory. Rejected because the failure (VM-wide PID exhaustion) affects other containers and has no legitimate use.

**Memory limit off by default.**
Build memory varies from a few hundred MiB to tens of GiB, and Docker Desktop and Colima already cap the VM.
A wrong default would break real work, so the limit is opt-in through `RAPUNZEL_MEMORY`.
Alternative: a default fraction of the VM's memory. Rejected: it needs a Docker info call and still guesses.

**Validate on the host, before Docker.**
`RAPUNZEL_PIDS_LIMIT` must be an integer ≥ 64; `RAPUNZEL_MEMORY` must match `^[0-9]+[bkmg]?$` (case-insensitive) and be at least 64 MiB, mirroring the `RAPUNZEL_PORT` check.
This keeps `--config` and the real run on one code path and gives a clear error instead of a Docker one.

**JetBrains: run configurations only.**
`.idea/runConfigurations` and `.run` hold run configurations shared in the project.
`.idea/workspace.xml` also holds them, but the IDE rewrites it constantly, so watching it would report changes on most runs and teach users to ignore the report.

**Claude Code subdirectories, not the whole `.claude`.**
`.claude/worktrees` can hold full checkouts; hashing them on every run is slow and noisy.
`commands`, `agents`, `skills`, and `hooks` are the parts the host's Claude Code loads or runs.

**Verify with cgroup files.**
`verify-isolation-inner.sh` reads `/sys/fs/cgroup/pids.max` and `memory.max` (cgroup v2 on Docker Desktop, Colima, and the Ubuntu CI runner) and compares them with values the outer script passes in.

## Risks / Trade-offs

- [A build needs more than 4096 processes] → The error is `fork: Resource temporarily unavailable`; the guide documents `RAPUNZEL_PIDS_LIMIT`.
- [cgroup v1 hosts] → The check fails clearly instead of passing; all tested platforms use v2.
- [Nested `build.rs` or crates outside the top level] → Documented as a limitation of the fixed path list.
