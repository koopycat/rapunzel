# container-isolation Specification

## Purpose

The agent container confines an untrusted harness to one host directory without root or capabilities, while keeping ordinary tooling (git, shells, Node) working under the caller's arbitrary UID. Sources: `rapunzel`, `Dockerfile`, `bootstrap.sh`, `setup-identity.sh`, `rapunzel-shell`, `verify-isolation.sh`.

## Requirements

### Requirement: Unprivileged agent process

The agent container SHALL run as the caller's numeric UID and GID with `--cap-drop=ALL`, `--security-opt=no-new-privileges`, and `--init`, and MUST be removed when it exits.

#### Scenario: No capabilities inside the container
- **WHEN** a process in the agent container reads its capability sets
- **THEN** the effective and bounding sets are empty and the process is not UID 0

#### Scenario: Files belong to the caller
- **WHEN** the agent creates a file in `/workspace`
- **THEN** the file on the host is owned by the invoking user

### Requirement: Only the project is bind-mounted

The only host bind mount SHALL be the requested project at `/workspace` (read-write), plus the read-only git sub-mounts defined by host-file protection. The host home directory, `~/.pi`, `~/.ssh`, and the Docker socket MUST NOT be mounted. The harness state comes from a named volume, never from a host path.

#### Scenario: Host paths invisible
- **WHEN** a process in the agent container probes `/Users`, `/Volumes`, the host home, `~/.ssh`, and `~/.pi` from inside the container
- **THEN** none are visible and the mount table has no host home mount

#### Scenario: Host root refused
- **WHEN** the user runs `rapunzel /`
- **THEN** the launcher refuses to mount the host root as a project

### Requirement: Resolvable identity without root

The entrypoint SHALL give the runtime UID/GID the name `agent` by writing a private passwd and group file into the state volume and preloading libnss-wrapper. `LD_PRELOAD` MUST be set to exactly that library, discarding any inherited value. This applies to both the harness entrypoint and the `--shell` entrypoint.

#### Scenario: whoami works for an arbitrary UID
- **WHEN** the launcher runs as UID 501 and the agent runs `whoami`
- **THEN** it prints `agent` and the shell prompt shows no "I have no name!"

#### Scenario: Inherited preload discarded
- **WHEN** the container starts with another `LD_PRELOAD` value somehow present
- **THEN** the harness runs with `LD_PRELOAD=/usr/local/lib/libnss_wrapper.so` only

### Requirement: Writable home for any UID

`/home/agent` and, in the pi image, `/home/agent/.pi` SHALL be mode 1777 so tools and extensions running as the caller's UID can write caches such as `~/.pi/cache`. `HOME` MUST be `/home/agent` and cannot be overridden from the host.

#### Scenario: Cache write
- **WHEN** an extension running as UID 1000 creates `~/.pi/cache/x`
- **THEN** the write succeeds

### Requirement: Git trusts the workspace

The image SHALL set `safe.directory=/workspace` system-wide, because Docker Desktop presents the mount root as owned by root.

#### Scenario: Git on Docker Desktop
- **WHEN** the agent runs `git status` in `/workspace` on Docker Desktop
- **THEN** git does not refuse the repository for dubious ownership

### Requirement: Immutable entrypoint

The entrypoint, shell entrypoint, and helper scripts SHALL be root-owned in the image so the runtime user cannot modify them.

#### Scenario: Agent tries to replace the entrypoint
- **WHEN** the agent writes to `/usr/local/bin/rapunzel-entrypoint`
- **THEN** the write fails with permission denied
