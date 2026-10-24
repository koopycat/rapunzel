# host-file-protection Specification

## Purpose

The agent can write anything in the mounted project, including files the host later runs on its own. rapunzel prevents the git cases where that keeps commits working, and reports changes to the other host-executed files after every run. Sources: `lib/host-files.sh`, `rapunzel`, `verify-host-files.sh`.

## Requirements

### Requirement: Read-only git control files

When the project has a real `.git` directory (not a file or symlink), the launcher SHALL mount `.git/config` and `.git/hooks` read-only over the project mount, creating `.git/hooks` first if it is missing. Symlinked config or hooks entries SHALL NOT be mounted. The agent MUST still be able to commit, branch, and stash.

#### Scenario: Agent plants a hook
- **WHEN** the agent writes `.git/hooks/pre-commit`
- **THEN** the write fails because the directory is read-only

#### Scenario: Agent sets fsmonitor
- **WHEN** the agent runs `git config core.fsmonitor ./evil`
- **THEN** the command fails and the host config is unchanged

#### Scenario: Commit still works
- **WHEN** the agent stages a change and runs `git commit`
- **THEN** the commit succeeds

#### Scenario: Clone without hooks directory
- **WHEN** a clone has no `.git/hooks`
- **THEN** the launcher creates it on the host before mounting it read-only

#### Scenario: Linked worktree
- **WHEN** the project's `.git` is a file pointing to a git directory elsewhere
- **THEN** no git sub-mounts are added and that directory stays outside the container

### Requirement: Read-only in-project hooks path

When the repository config sets `core.hooksPath` to a directory inside the project other than `.git/hooks`, that directory SHALL also be mounted read-only. The hooks path MUST be read with `git config --file` on the repository config only, so nothing from that config runs on the host.

#### Scenario: Husky hooks
- **WHEN** the repository sets `core.hooksPath=.husky`
- **THEN** `.husky` is read-only inside the container

#### Scenario: Hooks path outside the project
- **WHEN** `core.hooksPath` points to `/usr/share/hooks`
- **THEN** no extra mount is added, because the directory is not in the container anyway

### Requirement: Snapshot of host-executed files

Before the harness starts, the launcher SHALL hash every file under the host-executed paths that common host tools run or load without asking (direnv, editor and JetBrains run configurations, devcontainer, CI, pre-commit and husky, agent settings and project-local agent resources such as `.pi`, `.agents`, and Claude Code commands, agents, skills, and hooks, package manager, Cargo build configuration and a top-level `build.rs`, make/just, Nix/devenv/mise, git attributes and modules), the git control paths, an in-project `core.hooksPath`, and submodule configs and hooks. Symlinks SHALL be recorded by target.

#### Scenario: Package script
- **WHEN** the agent edits a script in `package.json`
- **THEN** the change is in the after-exit report

#### Scenario: Git internals included
- **WHEN** the snapshot is taken
- **THEN** it covers `.git/config`, `config.worktree`, `commondir`, `hooks`, `info`, `worktrees`, and `objects/info/alternates`

#### Scenario: Planted pi extension
- **WHEN** the agent adds a file under `.pi/extensions`
- **THEN** the after-exit report lists it as added

#### Scenario: Cargo build script
- **WHEN** the agent edits `build.rs` or `.cargo/config.toml`
- **THEN** the after-exit report lists it as modified

### Requirement: Change report for host-executed files

When the harness exits, the launcher SHALL compare a new snapshot with the first one, list every path that was added, modified, or removed, and ask the user to review them before running git, direnv, an editor, or build tools. No report SHALL be printed when nothing changed.

#### Scenario: Planted .envrc
- **WHEN** the agent creates `.envrc`
- **THEN** after exit the launcher prints `added: .envrc` under a review warning

#### Scenario: Retargeted symlink
- **WHEN** the agent changes where `.vscode/settings.json` (a symlink) points
- **THEN** the report lists it as modified

#### Scenario: Paths with spaces
- **WHEN** a changed file under `.github/workflows` has a space in its name
- **THEN** the report prints the full path
