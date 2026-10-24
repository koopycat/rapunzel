# Spec Delta

## MODIFIED Requirements

### Requirement: Only the project is bind-mounted

In mount mode, the only host bind mount SHALL be the requested project at `/workspace` (read-write), plus the read-only git sub-mounts defined by host-file protection. In clone mode, the agent container SHALL have no host bind mount; `/workspace` is the workspace volume. The host home directory, `~/.pi`, `~/.ssh`, and the Docker socket MUST NOT be mounted. The harness state comes from a named volume, never from a host path.

#### Scenario: Host paths invisible
- **WHEN** a process in the agent container probes `/Users`, `/Volumes`, the host home, `~/.ssh`, and `~/.pi` from inside the container
- **THEN** none are visible and the mount table has no host home mount

#### Scenario: Host root refused
- **WHEN** the user runs `rapunzel /`
- **THEN** the launcher refuses to mount the host root as a project

#### Scenario: Clone mode has no bind mount
- **WHEN** a process in a clone-mode agent container lists its mounts
- **THEN** `/workspace` and the state directory are volumes and no mount source is a host path
