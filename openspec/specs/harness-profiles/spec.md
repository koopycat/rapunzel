# harness-profiles Specification

## Purpose

A harness profile describes one coding-agent CLI (pi, Claude Code, Codex CLI, DeepSeek Harness, opencode) as data the launcher consumes. Profiles let new harnesses plug in without weakening any launcher control. Sources: `lib/profile.sh`, `profiles/<name>/profile.sh`, `Dockerfile`.

## Requirements

### Requirement: Profiles are repository data only

A profile SHALL be `profiles/<name>/profile.sh` in this repository and MUST only declare variables: `H_NAME`, `H_CMD`, `H_IMAGE`, `H_STATE_DIR`, `H_STATE_ENV`, `H_ENV_ALLOW`, `H_ENV_ALLOW_GATEWAY`, `H_ENV_DENY`, `H_OFFLINE_ENV`, `H_EGRESS_HOSTS`, `H_STRICT_SUPPORTED`, `H_DEFAULT_ARGS`, `H_WEB_PORT`, `H_WEB_PORT_ARG`. A profile MUST NOT weaken a launcher control. The launcher MUST NOT load a profile from a user-supplied path.

#### Scenario: Path-like harness name
- **WHEN** the user passes `--harness ../../tmp/evil`
- **THEN** the name fails the `^[a-z][a-z0-9-]*$` check and nothing is sourced

### Requirement: Profile validation

Loading a profile SHALL reset the optional `H_*` variables to defaults (strict supported, no extra names, no web port), then require non-empty `H_NAME`, `H_CMD`, `H_IMAGE`, and `H_STATE_DIR`, require `H_NAME` to equal the directory name, and require `H_STATE_DIR` to lie under `/home/agent/`. `H_STATE_ENV` MAY be empty for a harness without a single home variable.

#### Scenario: Mismatched name
- **WHEN** `profiles/foo/profile.sh` sets `H_NAME=bar`
- **THEN** loading fails and the launcher exits with status 2

#### Scenario: State outside home
- **WHEN** a profile sets `H_STATE_DIR=/etc/agent`
- **THEN** loading fails

### Requirement: One image stage per harness

The Dockerfile SHALL build a shared base stage and one final stage per harness, so one harness's dependencies never ship in another's image. The pi stage MUST be last so `docker build -t rapunzel .` builds pi, and each harness CLI version MUST be pinned by a `<NAME>_PACKAGE`/`<NAME>_VERSION` argument pair.

#### Scenario: Building a non-default harness
- **WHEN** the user runs `docker build --target opencode -t rapunzel:opencode .`
- **THEN** the image contains opencode and not pi

### Requirement: Per-harness state location

Each harness SHALL keep its configuration, logins, and sessions in its profile's `H_STATE_DIR`, pointed to by `H_STATE_ENV` when the harness has a single home variable.

| Harness | `H_STATE_DIR` | `H_STATE_ENV` |
|---|---|---|
| pi | `/home/agent/.pi/agent` | `PI_CODING_AGENT_DIR` |
| claude | `/home/agent/.claude` | `CLAUDE_CONFIG_DIR` |
| codex | `/home/agent/.codex` | `CODEX_HOME` |
| dsh | `/home/agent/.dsh` | `DSH_HOME` |
| opencode | `/home/agent/.opencode-state` | (empty) |

#### Scenario: Claude Code state relocated
- **WHEN** Claude Code starts
- **THEN** `CLAUDE_CONFIG_DIR=/home/agent/.claude`, so its global `.claude.json` is in the volume too

### Requirement: XDG state for opencode

For opencode, which has no single home variable, the image SHALL point `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME` into `H_STATE_DIR`, and the profile MUST deny those names and opencode's own config and database location variables from the host.

#### Scenario: opencode state persists
- **WHEN** opencode writes `auth.json` and sessions, and the user starts it again for the same project
- **THEN** both are still present, because all four XDG directories live in the volume

### Requirement: Strict mode support is declared per profile

The launcher SHALL refuse `RAPUNZEL_EGRESS=strict` with status 2 for a profile with `H_STRICT_SUPPORTED=false`. Currently pi, opencode, and claude support strict mode; codex and dsh do not.

#### Scenario: Codex in strict mode
- **WHEN** the user runs `RAPUNZEL_EGRESS=strict rapunzel-codex .`
- **THEN** the launcher exits with status 2 and suggests allowlist

#### Scenario: Claude Code in strict mode
- **WHEN** the user runs `RAPUNZEL_EGRESS=strict rapunzel-claude .` with `ANTHROPIC_API_KEY` set
- **THEN** the launcher starts the credential gateway and Claude Code

### Requirement: Vendor traffic switched off in restricted modes

In `allowlist` and `strict` mode the launcher SHALL set the profile's `H_OFFLINE_ENV` pairs, which switch off update checks, telemetry, and catalog fetches that have no route there. Those names are managed by the launcher in restricted modes and are not forwarded from the host.

#### Scenario: pi in allowlist mode
- **WHEN** pi runs with `RAPUNZEL_EGRESS=allowlist`
- **THEN** it receives `PI_OFFLINE=1`, `PI_SKIP_VERSION_CHECK=1`, and `PI_TELEMETRY=0`

#### Scenario: Claude Code in allowlist mode
- **WHEN** Claude Code runs with `RAPUNZEL_EGRESS=allowlist`
- **THEN** it receives `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_AUTOUPDATER=1`

### Requirement: Profile default arguments

A profile without a terminal UI MAY declare `H_DEFAULT_ARGS`; the launcher SHALL use them only when no harness arguments are given. dsh defaults to `web --patch /usr/local/lib/rapunzel/dsh-web.patch.yml --no-open`, whose patch makes dsh listen on all container interfaces while its launch token, session cookie, and Host check stay in force.

#### Scenario: dsh headless task
- **WHEN** the user runs `rapunzel --harness dsh --exec . dsh headless "task"`
- **THEN** no web UI starts and no port is published
