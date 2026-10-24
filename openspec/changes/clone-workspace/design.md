# Design

## Context

Today `/workspace` is a bind mount of the host checkout, protected by read-only sub-mounts of `.git/config`, `.git/hooks`, and an in-project `core.hooksPath` (`lib/host-files.sh`) and by a before/after hash report of other host-executed paths. Volumes are named and prepared by `lib/volumes.sh`; the image already ships git and sets `safe.directory=/workspace`.

## Goals / Non-Goals

**Goals:**
- No host path inside the agent container in clone mode.
- The host never runs git against, or reads config from, a repository the agent controlled.
- Agent work comes back as reviewable commits, without overwriting anything on the host.

**Non-Goals:**
- Copying uncommitted changes, untracked files (`.env`, `node_modules`), submodules, or LFS objects.
- Pushing agent commits anywhere or merging them; the user decides.
- Making clone the default.

## Decisions

**Bundles over stdin/stdout, in both directions.**
Host to workspace: the host's git runs `git bundle create - --branches --tags` in the host repository (trusted), and the helper reads it from stdin. Workspace to host: the helper runs `git bundle create - --branches` in the workspace and the host fetches the file.
A bundle is plain data: the host-side `git fetch <bundle>` reads no configuration and runs no hook from the agent's repository, and `-c transfer.fsckObjects=true` rejects malformed objects.
Alternatives: `git fetch /path/in/volume` on the host runs `upload-pack` inside the agent-controlled repository and reads its config; `ext::docker run ... git-upload-pack` needs `protocol.ext.allow` and still speaks a live protocol with an agent-controlled peer. A read-only bind of the host repository into the helper would reintroduce a host mount.

**Incremental bundles after the first run.**
The helper first prints the workspace's `refs/remotes/origin/*` object IDs; the host passes those it has as `^<oid>` exclusions so only new history is sent. An unknown or missing OID falls back to a full bundle. The return bundle likewise excludes the host's existing `refs/remotes/rapunzel-<harness>/*` tips when the workspace has those objects.

**Refspecs that cannot touch host branches.**
The host fetches `+refs/heads/*:refs/remotes/rapunzel-<harness>/*` with `--no-tags` and `--no-write-fetch-head`. Forced updates are fine there, because those refs mirror the workspace. Git validates the ref names in the bundle header.

**Helper container.**
The harness image with `--entrypoint git`, `--network none`, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, the caller's UID/GID, only the workspace volume at `/workspace`, `--rm`, and `HOME=/tmp`. It runs before the agent starts and after it exits, never concurrently with it.
The first clone sets `user.name` and `user.email` in the workspace repository from the host's `git config`, so agent commits have an author, and checks out the host's current branch, or the current commit detached.

**Review report from host-side history only.**
`git log` and `git diff-tree --name-only` run on the host against the fetched objects, which are now in the host repository and contain no config. Paths are matched against `HOST_EXECUTED_PATHS` from `lib/host-files.sh`, so both modes share one list.

**Uncommitted work stays in the volume.**
The helper's `git status --porcelain` after the run decides the message. Nothing is discarded; `docker volume rm` resets the workspace, as the guide will say.

**Mount mode stays unchanged.**
In clone mode the git sub-mounts and the host-file snapshot are skipped, because nothing on the host is writable by the agent.

## Risks / Trade-offs

- [Large repositories make the first bundle slow] → Only the first run sends full history; later runs are incremental.
- [Users expect untracked files such as `.env`] → The launcher names what is missing at start; the guide shows the env-file route for secrets.
- [A malicious ref name or huge bundle from the workspace] → Git validates ref names; the fetch only writes under `refs/remotes/rapunzel-<harness>/`; size is bounded by the volume. Disk exhaustion on the host is accepted as a local denial of service the user can see.
- [The agent rewrites history in the workspace] → Forced updates land only in the mirror refs; the report shows what is new relative to the host's previous mirror tip.

## Migration Plan

Opt-in; nothing changes for existing users. `AGENTS.md` and `docs/architecture.md` describe both modes; the bind-mount invariant becomes mode-specific.
