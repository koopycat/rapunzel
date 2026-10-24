## MODIFIED Requirements

### Requirement: Per-run sidecar on its own outbound bridge

Each sidecar SHALL join the internal network under a fixed alias (`egress` for Pipelock, `llm-proxy` for the gateway) and a second per-run outbound bridge with inter-container communication disabled. It MUST NOT join Docker's default bridge. Strict mode with a tool allowlist runs both sidecars on the same two networks; Pipelock is then the run's recorded sidecar and the gateway has its own container.

#### Scenario: Compromised sidecar
- **WHEN** an attacker controls the sidecar
- **THEN** it can reach the internet through its outbound network but not the user's other containers on the default bridge

#### Scenario: Strict mode with a tool allowlist
- **WHEN** strict mode runs with `RAPUNZEL_EGRESS_ALLOW` set
- **THEN** the agent's internal network has exactly two peers, `egress` and `llm-proxy`

### Requirement: Resources removed at exit

When the harness exits, the launcher SHALL remove every sidecar of the run (with its anonymous volumes) and both per-run networks, ignoring errors, as part of the cleanup that runs before any output.

#### Scenario: Normal exit
- **WHEN** a restricted-mode session ends normally
- **THEN** `docker ps --all --filter label=rapunzel.run=<id>` and `docker network ls --filter label=rapunzel.run=<id>` are empty

#### Scenario: Strict mode with a tool allowlist
- **WHEN** a strict session with `RAPUNZEL_EGRESS_ALLOW` ends
- **THEN** both the Pipelock and the gateway container are removed
