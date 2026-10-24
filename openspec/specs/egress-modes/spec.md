# egress-modes Specification

## Purpose

`RAPUNZEL_EGRESS` chooses how far the agent can reach: `open` (normal internet), `allowlist` (named HTTPS hosts through an SNI-checking proxy), or `strict` (fixed provider routes through a credential gateway). Both restricted modes share one fail-closed network layout with a per-run sidecar. Mode-specific rules are in `egress-allowlist` and `egress-strict`; decisions are recorded in `docs/egress.md`. Sources: `rapunzel`, `lib/egress.sh`.

## Requirements

### Requirement: Mode selection and incompatible settings

`RAPUNZEL_EGRESS` SHALL default to `open` and accept only `open`, `allowlist`, or `strict`; any other value exits with status 2. In `open` mode the agent uses `RAPUNZEL_NETWORK` (default `bridge`; `none` for offline). The launcher MUST exit with status 2 when `RAPUNZEL_NETWORK` is combined with a restricted mode, or when `RAPUNZEL_EGRESS_ALLOW_PRIVATE` or `RAPUNZEL_EGRESS_LOGINS` is set outside `allowlist`.

#### Scenario: Offline open mode
- **WHEN** the user runs with `RAPUNZEL_NETWORK=none`
- **THEN** the agent container has no network

#### Scenario: Logins in strict mode
- **WHEN** `RAPUNZEL_EGRESS=strict` and `RAPUNZEL_EGRESS_LOGINS=anthropic`
- **THEN** the launcher exits with status 2, explaining that strict mode cannot keep `/login` credentials out

### Requirement: Fail-closed internal network

In a restricted mode the agent SHALL join only a per-run `--internal` network created with isolated gateway mode for IPv4 and IPv6, so it has no route off the network, no external DNS, and no address on the host side of the bridge. If isolated gateway mode is unavailable (Docker Engine older than 28), the launcher MUST fail rather than fall back to a plain internal network.

#### Scenario: Direct connection ignoring the proxy
- **WHEN** the agent opens a TCP connection straight to a public IPv4 or IPv6 address, a cloud metadata address, or a listener on the host
- **THEN** the connection fails

#### Scenario: Internal network cannot be created
- **WHEN** creating the isolated internal network fails, for example because Docker Engine 27 rejects the gateway-mode option
- **THEN** the launcher reports that `RAPUNZEL_EGRESS` needs Docker Engine 28 or newer and does not start the agent

### Requirement: Per-run sidecar on its own outbound bridge

Each sidecar SHALL join the internal network under a fixed alias (`egress` for Pipelock, `llm-proxy` for the gateway) and a second per-run outbound bridge with inter-container communication disabled. It MUST NOT join Docker's default bridge. Strict mode with a tool allowlist runs both sidecars on the same two networks; Pipelock is then the run's recorded sidecar and the gateway has its own container.

#### Scenario: Compromised sidecar
- **WHEN** an attacker controls the sidecar
- **THEN** it can reach the internet through its outbound network but not the user's other containers on the default bridge

#### Scenario: Strict mode with a tool allowlist
- **WHEN** strict mode runs with `RAPUNZEL_EGRESS_ALLOW` set
- **THEN** the agent's internal network has exactly two peers, `egress` and `llm-proxy`

### Requirement: Hardened sidecar container

The sidecar SHALL run as a fixed non-root UID with a read-only root filesystem, a tmpfs `/tmp`, all capabilities dropped (Caddy keeps only `NET_BIND_SERVICE`), `no-new-privileges`, a 256-process limit, and 512 MiB of memory.

#### Scenario: Fork bomb through the proxy
- **WHEN** a process in the sidecar tries to spawn more than 256 processes
- **THEN** the extra forks fail

### Requirement: Config delivery and readiness

The sidecar configuration MUST be delivered without host bind mounts: `docker cp` into an anonymous volume for Pipelock, an environment value for Caddy. The launcher MUST wait until a readiness probe run inside the sidecar with `docker exec` (Pipelock's `healthcheck`, or `/healthz` on Caddy) succeeds and, if it does not within 50 attempts 0.1 s apart, print its last log lines and fail.

#### Scenario: Remote Docker context
- **WHEN** the Docker engine runs on another machine without access to the host's files
- **THEN** the sidecar still receives its configuration

#### Scenario: Sidecar never healthy
- **WHEN** Pipelock rejects its configuration at startup
- **THEN** the launcher prints the sidecar's last 20 log lines and does not start the agent

### Requirement: Sidecar images pinned by digest

The Pipelock and Caddy images SHALL be pinned by tag and multi-arch digest in `lib/egress.sh`. Renovate MAY propose updates but MUST NOT automerge them, and any change there must keep `./verify-egress.sh` passing.

#### Scenario: Upstream retags an image
- **WHEN** the `caddy:2.11.7-alpine` tag is moved upstream
- **THEN** rapunzel keeps running the digest it pinned

### Requirement: Resource labels and stale sweep

Every per-run network, sidecar, and validator SHALL carry `rapunzel.egress=1`, `rapunzel.run=<run id>`, and `rapunzel.owner=<host>/<PID>`, where the PID is the launcher's, or the controller's for a validator. Before creating its own networks, a restricted run SHALL remove labeled sidecars and networks from the same host whose launcher PID no longer exists. It MUST NOT touch resources whose PID is alive (even if reused) or that belong to another host sharing the daemon.

#### Scenario: Launcher killed with SIGKILL
- **WHEN** a previous launcher was killed and left its sidecar and networks
- **THEN** the next restricted run on that host removes them before creating its own

#### Scenario: Concurrent run on the same daemon
- **WHEN** another live launcher on the same host owns a sidecar
- **THEN** the sweep leaves it running

### Requirement: Resources removed at exit

When the harness exits, the launcher SHALL remove every sidecar of the run (with its anonymous volumes) and both per-run networks, ignoring errors, as part of the cleanup that runs before any output.

#### Scenario: Normal exit
- **WHEN** a restricted-mode session ends normally
- **THEN** `docker ps --all --filter label=rapunzel.run=<id>` and `docker network ls --filter label=rapunzel.run=<id>` are empty

#### Scenario: Strict mode with a tool allowlist
- **WHEN** a strict session with `RAPUNZEL_EGRESS_ALLOW` ends
- **THEN** both the Pipelock and the gateway container are removed
