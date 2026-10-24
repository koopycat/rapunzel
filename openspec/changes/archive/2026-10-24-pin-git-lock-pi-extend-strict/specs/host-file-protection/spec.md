## MODIFIED Requirements

### Requirement: Read-only git control files

When the project has a real `.git` directory (not a file or symlink), the launcher SHALL first mount `.git` onto its own path, so the agent cannot rename it and leave a fresh `.git` for the host's git, and then mount `.git/config` and `.git/hooks` read-only over it, creating `.git/hooks` first if it is missing. A symlinked `.git/config` or `.git/hooks` MUST stop the launch. The agent MUST still be able to commit, branch, and stash.

#### Scenario: Agent plants a hook
- **WHEN** the agent writes `.git/hooks/pre-commit`
- **THEN** the write fails because the directory is read-only

#### Scenario: Agent sets fsmonitor
- **WHEN** the agent runs `git config core.fsmonitor ./evil`
- **THEN** the command fails and the host config is unchanged

#### Scenario: Agent swaps the git directory
- **WHEN** the agent runs `mv .git .git-moved` to replace `.git` with one holding its own hooks
- **THEN** the rename fails, and no `.git-moved` or planted hook appears on the host

#### Scenario: Symlinked hooks directory
- **WHEN** the project's `.git/hooks` is a symlink
- **THEN** the launcher exits before starting the agent and names the path, because a dangling mount target could be replaced inside the container

#### Scenario: Commit still works
- **WHEN** the agent stages a change and runs `git commit`
- **THEN** the commit succeeds

#### Scenario: Clone without hooks directory
- **WHEN** a clone has no `.git/hooks`
- **THEN** the launcher creates it on the host before mounting it read-only

#### Scenario: Linked worktree
- **WHEN** the project's `.git` is a file pointing to a git directory elsewhere
- **THEN** no git sub-mounts are added and that directory stays outside the container
