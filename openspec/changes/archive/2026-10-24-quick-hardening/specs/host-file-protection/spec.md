# Spec Delta

## MODIFIED Requirements

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
