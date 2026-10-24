# Spec Delta

## MODIFIED Requirements

### Requirement: Run modes

The launcher SHALL support five mutually exclusive modes after the optional `--harness` flag and the optional `--clone` flag: the default harness run, `--shell` (an interactive bash with the same mounts and environment), `--exec PROJECT_DIR COMMAND [ARGS...]` (run COMMAND instead of the harness), `--config [PROJECT_DIR]` (print the effective configuration without contacting Docker), and `--fetch [PROJECT_DIR]` (fetch the clone workspace's branches without starting the harness). `--clone`, or `RAPUNZEL_WORKSPACE=clone`, SHALL select the clone workspace for the run modes; `RAPUNZEL_WORKSPACE` MUST be `mount` or `clone`. `--shell`, `--config`, and `--fetch` MUST reject extra arguments, and `--shell` MUST require a TTY on stdin and stdout.

#### Scenario: Shell without a terminal
- **WHEN** `rapunzel --shell .` runs with stdin redirected from a file
- **THEN** it exits with status 2 and states that `--shell` requires an interactive terminal

#### Scenario: Exec mode for checks
- **WHEN** a check script runs `rapunzel --exec . node /probe.mjs`
- **THEN** the probe runs in a container with the launcher's real mounts, environment, and network instead of the harness

#### Scenario: Config mode does not touch Docker
- **WHEN** `rapunzel --config .` runs with no Docker engine reachable
- **THEN** it prints the configuration report and exits 0 without building images, creating volumes, or registering a run

#### Scenario: Fetch without a workspace
- **WHEN** `rapunzel --fetch .` runs for a project that has no workspace volume
- **THEN** it exits with status 1 and states that there is no clone workspace yet

#### Scenario: Invalid workspace mode
- **WHEN** `RAPUNZEL_WORKSPACE=copy` is set
- **THEN** the launcher exits with status 2 and names the valid values
