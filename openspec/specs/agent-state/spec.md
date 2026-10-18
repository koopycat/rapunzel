# agent-state Specification

## Purpose

Harness settings, logins, sessions, trust decisions, and extensions persist in a Docker named volume per project and per harness, so state never mixes between projects or harnesses and the host's own agent directories stay out of reach. Sources: `lib/volumes.sh`, `rapunzel`, `rapunzel-ext`.

## Requirements

### Requirement: Per-project, per-harness volume

The default state volume SHALL be named `rapunzel-<harness>-<hash>`, where `<hash>` is the first 12 hex digits of the SHA-256 of the canonical project path, and SHALL be mounted at the profile's `H_STATE_DIR` with `volume-nocopy`. `RAPUNZEL_VOLUME` MAY name a volume explicitly.

#### Scenario: Two harnesses on one project
- **WHEN** the user runs pi and then Claude Code on `/home/u/proj`
- **THEN** they use two different volumes, `rapunzel-pi-<h>` and `rapunzel-claude-<h>`, with the same hash

#### Scenario: Same project via a symlink
- **WHEN** the user starts the launcher through a symlinked path to the same project
- **THEN** the canonical path, and therefore the volume, is the same

### Requirement: Volume ownership preparation

Before every run, the launcher SHALL hand the volume to the caller's UID/GID in a short-lived container that runs as root with only `CHOWN` and `DAC_OVERRIDE`, `no-new-privileges`, and no network. This step MUST run on every platform, including Docker Desktop, and MUST refuse to run for UID 0.

#### Scenario: New volume
- **WHEN** a project runs for the first time
- **THEN** the root-owned new volume is chowned to the caller and the marker is written

### Requirement: Idempotent preparation marker

The preparation SHALL record `UID:GID` in the marker file `.owner-initialized` and exit without changes when the marker is a regular file with the caller's `UID:GID`. The marker MUST be removed before being rewritten, so a planted symlink is replaced rather than followed.

#### Scenario: Second run as the same user
- **WHEN** the volume's marker already holds the caller's `UID:GID`
- **THEN** the preparation container changes nothing

#### Scenario: Planted marker symlink
- **WHEN** the agent replaced `.owner-initialized` with a symlink to another file in the volume
- **THEN** the next preparation treats the volume as unprepared, re-chowns it, and writes a regular marker file

### Requirement: Host agent directories are never used

The launcher MUST NOT mount the host `~/.pi` or any other host harness directory as state, because they hold credentials, code-running extensions, and every project's history.

#### Scenario: Host pi login
- **WHEN** the user is logged in to pi on the host
- **THEN** a sandboxed pi session does not see that login

### Requirement: Curated extension sync

`rapunzel-ext sync [PROJECT_DIR]` SHALL copy the top-level entries of a curated host directory (`RAPUNZEL_EXTENSIONS_DIR`, default `~/.pi-extensions`) into the pi state volume's `extensions/`, dereferencing symlinks, dropping AppleDouble `._*` files at any depth, and preserving unrelated installed extensions. The tool always uses the pi profile; `RAPUNZEL_VOLUME` overrides the project-derived volume.

#### Scenario: Sync into an existing volume
- **WHEN** the volume already contains extension `a` and the curated directory contains `b`
- **THEN** after sync both `a` and `b` are installed, and the tool tells the user to run `/reload` in pi

#### Scenario: Missing source
- **WHEN** the curated directory does not exist
- **THEN** `sync` exits with status 1

### Requirement: Unprivileged extension copy

The sync copy MUST run as the caller's UID with no network, no capabilities, and `no-new-privileges`, after volume ownership preparation, with the staged source mounted read-only.

#### Scenario: Extension with an install hook
- **WHEN** a curated extension contains scripts
- **THEN** nothing in it runs during sync; the files are only copied

### Requirement: Extension listing

`rapunzel-ext list [PROJECT_DIR]` SHALL print the volume name, the curated entries, and the installed entries, reading the volume read-only with no network. A missing curated directory or volume SHALL be reported, not treated as an error.

#### Scenario: Project never run
- **WHEN** the project's volume does not exist yet
- **THEN** `list` prints `(volume does not exist)` and exits 0
