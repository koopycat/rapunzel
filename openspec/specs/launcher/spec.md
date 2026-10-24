# launcher Specification

## Purpose

The host-side `rapunzel` command turns one project directory and one harness profile into a single sandboxed `docker run`. It resolves arguments, refuses unsafe invocations, prepares the image and state volume, delegates to the environment, egress, and host-file capabilities, and cleans up after the harness exits. Sources: `rapunzel`, `lib/docker.sh`.

## Requirements

### Requirement: Harness selection

The launcher SHALL select the harness profile from, in increasing precedence: the default `pi`, the `RAPUNZEL_HARNESS` variable, the invoked name `rapunzel-<name>`, and a leading `--harness NAME` argument. The launcher MUST load the profile before any other work and exit with status 2 when it is unknown or invalid.

#### Scenario: Link name selects the harness
- **WHEN** the user runs `./rapunzel-claude .` with `RAPUNZEL_HARNESS=codex` set
- **THEN** the claude profile is loaded

#### Scenario: Explicit flag wins over the link name
- **WHEN** the user runs `./rapunzel-claude --harness opencode .`
- **THEN** the opencode profile is loaded

#### Scenario: Unknown harness
- **WHEN** the user runs `./rapunzel --harness nope`
- **THEN** the launcher prints the available profile names and exits with status 2

### Requirement: Project directory resolution

The first positional argument SHALL be the project directory and default to the current directory; any further arguments SHALL be passed to the harness. The launcher MUST resolve the directory to its canonical physical path before using it for mounts, volume names, or metadata.

#### Scenario: Default project
- **WHEN** the user runs `rapunzel` with no arguments in `/home/u/proj`
- **THEN** `/home/u/proj` (symlinks resolved) is mounted at `/workspace` and the harness starts with no arguments

#### Scenario: Harness arguments without a project directory
- **WHEN** the user runs `rapunzel --continue`
- **THEN** the launcher reports that the project directory `--continue` does not exist, suggests `rapunzel . --continue`, and exits with status 1

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

### Requirement: Refuse to run as root

The launcher MUST refuse to start when the invoking UID is 0.

#### Scenario: Root caller
- **WHEN** root runs `rapunzel .`
- **THEN** it prints that it refuses to run as root and exits with status 1

### Requirement: Docker reachability check

Every launcher and check script SHALL verify that the Docker engine responds before its first Docker call. When it does not, the script MUST print the original error, the active `DOCKER_HOST` or context, platform-specific advice for starting an engine (Colima, Docker Desktop, systemd), and how to switch contexts, then exit with status 1.

#### Scenario: Colima stopped
- **WHEN** the active context is `colima` and the engine is down
- **THEN** the message includes the first lines of the Docker error and suggests `colima start`

### Requirement: Missing local image is built on first use

When the selected image name has no registry component (no `/`) and does not exist locally, the launcher SHALL build it from the checkout's Dockerfile using the profile's stage as the target, sending build output to stderr. Registry references MUST be left to Docker.

#### Scenario: First run of a non-default harness
- **WHEN** `rapunzel:codex` is missing and the user runs `rapunzel-codex .`
- **THEN** the launcher runs `docker build --target codex -t rapunzel:codex <checkout>` before starting

#### Scenario: Registry image
- **WHEN** `RAPUNZEL_IMAGE=ghcr.io/koopycat/rapunzel` is set
- **THEN** the launcher does not build and lets Docker pull the image

### Requirement: Interactive TTY handling

The launcher SHALL allocate an interactive TTY only when both stdin and stdout are terminals.

#### Scenario: Piped output
- **WHEN** the launcher's stdout is a pipe
- **THEN** the container runs without `--interactive --tty`

### Requirement: Terminal restore after interactive sessions

After an interactive session the launcher SHALL reset terminal modes a harness may leave enabled: leave the alternate screen without restoring a cursor (1047), pop the kitty keyboard protocol stack, disable modifyOtherKeys, mouse, focus, and color-scheme reporting, and show the cursor. The reset MUST be a no-op after a clean harness exit and MUST NOT run when no TTY was used.

#### Scenario: Container killed mid-session
- **WHEN** the harness container is killed while pi has the kitty keyboard protocol on
- **THEN** the shell afterwards receives plain keys, not CSI-u sequences

### Requirement: Cleanup on every exit

On exit the launcher SHALL, with errexit off and SIGHUP ignored, first remove the filtered env file, the egress sidecar and networks, the run record, and the egress temp directory, and only then restore the terminal and print the host-file report. Releasing secrets and network resources MUST NOT depend on the terminal still being writable.

#### Scenario: Terminal pane closed
- **WHEN** the user closes the terminal pane running a restricted-mode session
- **THEN** the sidecar, both per-run networks, and the filtered env file are removed even though writes to the terminal fail

### Requirement: Loopback-only web UI publishing

The launcher SHALL publish no ports, except for a profile with a web UI (`H_WEB_PORT`) started with its default arguments in `open` egress mode. That port MUST be bound to the host's `127.0.0.1` only, MAY be overridden by `RAPUNZEL_PORT` in the range 1024–65535, and the harness's own authentication MUST stay on. Explicit harness arguments replace the defaults and publish nothing.

#### Scenario: dsh web UI
- **WHEN** the user runs `rapunzel-dsh .`
- **THEN** dsh starts `web` with the rapunzel patch and `--port 3080`, and the container publishes `127.0.0.1:3080:3080`

#### Scenario: Web UI in a restricted mode
- **WHEN** the user runs `RAPUNZEL_EGRESS=allowlist rapunzel-dsh .`
- **THEN** the launcher exits with status 2 because restricted modes have no published ports

#### Scenario: Invalid port
- **WHEN** `RAPUNZEL_PORT=80` is set for dsh
- **THEN** the launcher exits with status 2

### Requirement: Host time zone

The launcher SHALL pass the host time zone as `TZ`, taken from `TZ` or the `/etc/localtime` symlink, in every egress mode, and only when the value matches a plain zone-name pattern.

#### Scenario: Zone from localtime
- **WHEN** `TZ` is unset and `/etc/localtime` links to `/usr/share/zoneinfo/Europe/Berlin`
- **THEN** the container receives `TZ=Europe/Berlin`

#### Scenario: Malformed TZ
- **WHEN** `TZ` contains a space or shell metacharacters
- **THEN** no `TZ` is passed

### Requirement: Symlink-safe checkout location

The launcher and its sibling tools SHALL follow symlinks to their own script so that a link on `PATH` still loads `lib/` and `profiles/` from the checkout.

#### Scenario: Link on PATH
- **WHEN** `~/bin/rapunzel` links to the checkout's `rapunzel`
- **THEN** running `rapunzel` sources the checkout's libraries
