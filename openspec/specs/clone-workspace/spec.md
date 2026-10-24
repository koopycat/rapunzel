# clone-workspace Specification

## Purpose

Lets the agent work on a container-local git clone of the project, so nothing it writes reaches the host checkout, and its work returns only as commits the host fetches as data and the user reviews before merging.

## Requirements

### Requirement: Workspace volume

In clone mode, `/workspace` SHALL be a named volume `rapunzel-<harness>-<hash>-workspace`, derived like the state volume and owned by the caller's UID, that persists between runs. Clone mode MUST refuse a project that is not a git repository with at least one commit.

#### Scenario: First run
- **WHEN** the user runs `rapunzel --clone .` in a repository for the first time
- **THEN** the workspace volume is created and holds a clone with the host's current branch checked out

#### Scenario: Not a repository
- **WHEN** the user runs `rapunzel --clone` in a directory without `.git`
- **THEN** the launcher exits with an error before creating any Docker resource

### Requirement: Host history enters as a bundle

Before each run, the launcher SHALL create a git bundle of the host repository's branches and tags with the host's git and pass it on stdin to a helper container from the harness image that runs with no network, no capabilities, the caller's UID, and only the workspace volume mounted. The first run SHALL clone it; later runs SHALL fetch it into `refs/remotes/origin/*` and MUST NOT change the agent's branches, index, or working tree.

#### Scenario: Host commits since the last run
- **WHEN** the user commits on the host and starts the next clone run
- **THEN** the agent sees the new commit on `origin/<branch>`, and its own branch is unchanged

#### Scenario: No host mount in the helper
- **WHEN** the helper container runs
- **THEN** its mount table contains only the workspace volume

### Requirement: Agent history returns as a bundle

After each run, and on `rapunzel --fetch`, the helper SHALL write a bundle of the workspace's branches to stdout. The host SHALL fetch it with `transfer.fsckObjects=true` into `refs/remotes/rapunzel-<harness>/*` only, never into local branches or tags, and MUST NOT run git inside the workspace repository on the host or read its configuration.

#### Scenario: Agent commits
- **WHEN** the agent commits on `main` in the workspace and exits
- **THEN** the host has the commit at `refs/remotes/rapunzel-pi/main` and its own `main` is unchanged

#### Scenario: Planted hook stays inside
- **WHEN** the agent writes `.git/hooks/pre-commit` and sets `core.fsmonitor` in the workspace repository
- **THEN** after the fetch the host repository's hooks and config are unchanged

#### Scenario: Agent tags ignored
- **WHEN** the agent creates a tag in the workspace
- **THEN** the fetch does not create or move any tag on the host

### Requirement: Review report

After the fetch, the launcher SHALL print, per fetched branch, the commits that are new on the host, and SHALL warn about every new commit that adds, changes, or removes a host-executed path from the host-file list. It SHALL also report when the workspace has uncommitted changes, which stay in the volume for the next run.

#### Scenario: Commit adds an .envrc
- **WHEN** a fetched commit adds `.envrc`
- **THEN** the report names that commit and `.envrc` under a review warning

#### Scenario: Uncommitted work
- **WHEN** the agent exits with modified files it did not commit
- **THEN** the launcher states that the changes remain in the workspace volume and were not fetched

### Requirement: Not copied into the workspace

Clone mode SHALL copy only committed history. Before the first run, the launcher SHALL say when the host checkout has uncommitted changes or untracked files that the workspace will not contain. Submodules and Git LFS objects are not provided.

#### Scenario: Dirty host checkout
- **WHEN** the host checkout has an uncommitted change at the start of a clone run
- **THEN** the launcher prints that the change is not in the workspace and continues
