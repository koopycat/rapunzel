# Proposal

## Why

rapunzel's highest-ranked residual risk is files the host later runs: the agent can plant `.envrc`, editor tasks, or package scripts in the mounted project, and rapunzel only reports them after the run.
The read-only git sub-mounts that block hooks are also nested bind mounts, which shut down Docker Desktop's VM twice.
A workspace the agent works on as a container-local git clone removes both problems: nothing it writes touches the host checkout, and its work comes back as commits the user reviews before merging. Docker Sandboxes already ships this model; rapunzel lists it as future work.

## What Changes

- New workspace mode `clone`, selected with `RAPUNZEL_WORKSPACE=clone` or `--clone`. The default stays `mount`.
- In clone mode the agent's `/workspace` is a per-project, per-harness named volume holding a git clone. The launcher adds no host bind mount at all.
- Host to workspace: before each run the launcher sends the host repository's branches and tags as a git bundle through stdin into a short-lived, networkless helper container, which clones (first run) or fetches them into `refs/remotes/origin/*` (later runs). The agent's own branches and working tree are left alone.
- Workspace to host: after each run the helper writes the workspace's branches as a git bundle to stdout; the host fetches it with object checking into `refs/remotes/rapunzel-<harness>/*`, and prints the new commits plus every commit that touches a host-executed path.
- `rapunzel --fetch [PROJECT_DIR]` repeats the fetch without starting the harness.
- The git sub-mounts and the host-file snapshot apply only in mount mode.
- Clone mode needs a git repository with at least one commit; uncommitted host changes and untracked files are not copied, and the launcher says so.

## Capabilities

### New Capabilities

- `clone-workspace`: the clone workspace's lifetime, how history moves between host and workspace, and what the host trusts from it.

### Modified Capabilities

- `container-isolation`: in clone mode there is no host bind mount.
- `launcher`: `--clone` and `--fetch`.
- `config-inspection`: the report shows the workspace mode and volume.
- `verification-and-release`: a new check script for clone mode, run in CI.

## Impact

- `rapunzel`, new `lib/workspace.sh`, `lib/volumes.sh` (workspace volume name and ownership), `lib/policy.sh` (report).
- New `verify-workspace.sh`; `.github/workflows/ci.yml`; `AGENTS.md` invariants (only host bind mount), `docs/architecture.md`, `docs/guide.md`, `README.md`.
- No change for users who do not opt in.
