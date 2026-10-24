# Proposal

## Why

A comparison with other agent sandboxes found three small gaps.
The agent container has no process or memory limit, so a fork bomb or runaway build can starve the Docker VM and every other container on it; the sidecars already have limits.
The host-file report misses several paths that host tools run or load on their own, most notably pi's project-local `.pi` resources and `.agents/skills`, which the guide itself says stay visible in the project.
`docs/egress.md` names Pipelock 3.6.0 as the current pin while `lib/egress.sh` pins 3.7.1.

## What Changes

- The agent container gets `--pids-limit` (default 4096, override with `RAPUNZEL_PIDS_LIMIT`) and an optional `--memory` limit (`RAPUNZEL_MEMORY`, unset by default). Invalid values stop the launcher before Docker runs. `--config` and `rapunzel-ctl config` show the effective limits.
- The host-executed paths gain `.pi`, `.agents`, `.claude/commands`, `.claude/agents`, `.claude/skills`, `.claude/hooks`, `.cargo/config.toml`, `.cargo/config`, `build.rs`, `.idea/runConfigurations`, and `.run`.
- `docs/egress.md` stops naming a current Pipelock version and points at `lib/egress.sh`; the 3.5.0 test record stays as history.
- The allowlist proxy no longer rate-limits tunnels. Pipelock's default of 60 tunnels per host and minute answered `429` to ordinary bursts (parallel model calls, an allowed package registry) and caused intermittent check failures; the limit counts tunnels, not data, so it does not bound exfiltration in a local setup.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `container-isolation`: the agent process gets a process limit and an optional memory limit.
- `host-file-protection`: the snapshot covers agent resources, Cargo build configuration, and JetBrains run configurations.
- `config-inspection`: the effective configuration includes the resource limits.
- `egress-allowlist`: the proxy has no effective request rate limit.

## Impact

- `rapunzel`, `lib/policy.sh`, `lib/host-files.sh`, `lib/ctl-output.jq` (text rendering of the config, if it lists fields explicitly).
- `verify-isolation-inner.sh` / `verify-isolation.sh`, `verify-host-files.sh`, `test-control.sh`.
- `docs/guide.md`, `docs/architecture.md`, `docs/egress.md`, `README.md` if it lists variables.
- Users whose builds legitimately exceed 4096 processes need `RAPUNZEL_PIDS_LIMIT`; nobody is affected by memory unless they set it.
