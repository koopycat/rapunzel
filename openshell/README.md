# OpenShell blueprint for local repositories

This directory is an alternative to the repository's plain-Docker runner. It is
for higher-risk projects where Pi should not receive a host bind mount, general
network access, or a real provider API key.

## Security model

The default workflow:

1. Copies tracked and non-ignored files into a sanitized Git snapshot at `/workspace`.
2. Gives the sandbox no ordinary outbound network access.
3. Attaches one OpenShell provider whose real key stays outside the sandbox.
4. Requires Landlock filesystem enforcement and a non-root process.
5. Limits the sandbox to 4 CPUs and 8 GiB by default.
6. Keeps all edits in the sandbox until an explicit export into a new directory.

It deliberately does **not** bind-mount the local repository or download changes
over it. Review the exported tree or diff it against the source before applying
changes.

This is a blueprint, not an OpenShell installer. It was exercised against the
CLI contract in OpenShell `0.0.77`; current NVIDIA docs describe the newer 0.1.x
line. OpenShell is evolving, so review `openshell ... --help`, the upgrade guide,
and the linked docs before upgrading.

## Files

- `Dockerfile`: pinned Pi release and base-image digest for OpenShell.
- `policy.yaml`: default deny-network policy and mandatory Landlock policy.
- `provider-anthropic.yaml`: Anthropic endpoint and credential profile.
- `network-development.example.yaml`: optional package/Git read policy.
- `setup-provider`: imports a profile and stores its key with OpenShell.
- `pi-openshell`: creates, reconnects to, exports, and deletes sandboxes.

## Prerequisites

Install OpenShell and start or select a gateway according to the
[OpenShell installation guide](https://docs.nvidia.com/openshell/about/installation).
The gateway must be able to resolve the locally built image. With the local
Docker gateway, build it as follows:

```bash
docker build -t pi-openshell:local -f openshell/Dockerfile .
```

For a remote gateway, publish the image to a registry and set
`OPENSHELL_PI_IMAGE` to the registry reference. Do not grant registry access to
the running agent merely to solve image distribution; image pulling belongs to
the sandbox infrastructure.

## Configure one provider

Anthropic:

```bash
read -rs ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY
./openshell/setup-provider anthropic
unset ANTHROPIC_API_KEY
```

`setup-provider` passes the credential to the OpenShell control plane, not the
sandbox. Pi sees a placeholder. OpenShell substitutes the real credential only
for a request matching the provider's endpoint and executable restrictions.

If the provider already exists, inspect it with `openshell provider get` rather
than recreating it.

## Work on a local repository

From this repository:

```bash
./openshell/pi-openshell create ~/src/my-project
```

Pass Pi arguments after `--`:

```bash
./openshell/pi-openshell create ~/src/my-project -- --model anthropic/claude-sonnet-4-6
```

The default sandbox name is derived from the canonical project path. The name
printed by `create` is the one to use below. Override it when multiple concurrent
copies are needed:

```bash
OPENSHELL_PI_NAME=pi-my-project-review \
  ./openshell/pi-openshell create ~/src/my-project
```

Reconnect or run a command later:

```bash
./openshell/pi-openshell connect pi-my-project-ab12cd34
./openshell/pi-openshell exec pi-my-project-ab12cd34 git status --short
```

Inspect effective controls from another terminal:

```bash
openshell policy get pi-my-project-ab12cd34 --full
openshell sandbox provider list pi-my-project-ab12cd34
openshell logs pi-my-project-ab12cd34 --tail
```

## Retrieve changes safely

Export only to a new or empty directory:

```bash
./openshell/pi-openshell export \
  pi-my-project-ab12cd34 \
  ~/src/reviews/my-project-openshell
```

Then review without touching the source repository:

```bash
diff -ruN \
  --exclude=.git \
  ~/src/my-project/ \
  ~/src/reviews/my-project-openshell/
```

Apply selected changes with your normal Git tooling only after review. Finally:

```bash
./openshell/pi-openshell delete pi-my-project-ab12cd34
```

## What gets uploaded

`pi-openshell` creates a temporary snapshot from Git's tracked files plus
non-ignored untracked files. It rejects common credential filenames unless
`OPENSHELL_PI_ALLOW_SENSITIVE_UPLOAD=1` is set, then creates fresh Git metadata
with no host remotes, hooks, config, or history. However:

- Tracked secrets with unrecognized names are still uploaded.
- Untracked files not covered by `.gitignore` are uploaded.
- Filename checks and `.gitignore` are not a secret scanner.
- Files uploaded to a remote gateway leave the local machine.

Before using an unfamiliar repository, review its tracked and untracked files:

```bash
git status --short --ignored
git ls-files
```

For especially sensitive work, create a separate sanitized worktree or export a
reviewed source archive and point `pi-openshell create` at that directory.

## Granting additional network access

The default `policy.yaml` contains no ordinary network rule. Attached providers
contribute reserved `_provider_*` rules only for inference. Commands such as
`git fetch`, `curl`, and package installation fail unless policy explicitly
allows them.

To enable selected development endpoints:

```bash
cp openshell/network-development.example.yaml /tmp/my-project-policy.yaml
$EDITOR /tmp/my-project-policy.yaml
OPENSHELL_PI_POLICY=/tmp/my-project-policy.yaml \
  ./openshell/pi-openshell create ~/src/my-project
```

Treat `network-development.example.yaml` as a starting point, not a universal
allowlist:

- Remove every endpoint the project does not need.
- Prefer exact hosts over wildcard hosts.
- Keep package registries read-only.
- Restrict each endpoint to the actual executable that needs it.
- Do not allow cloud metadata, LAN ranges, arbitrary proxies, or the host Docker
  socket.
- Keep `--approval-mode manual`; review agent-authored policy proposals instead
  of automatically applying them.

Static filesystem and process policy is fixed when a sandbox is created.
Network policy can be changed on a running sandbox, but each change expands the
sandbox's authority and should be reviewed like code.

## Trust boundaries and limitations

This workflow protects the original working tree from direct writes and keeps
provider keys outside the workload. It does not make uploaded source secret from
the sandbox or from an attached remote gateway administrator.

An allowed inference endpoint is still a data channel: Pi necessarily sends
prompts and source context to the selected model provider. Network policy also
cannot stop sensitive data from being encoded into an operation that policy
intentionally allows. Use providers and gateways appropriate for the project's
data classification.

The exported directory is untrusted output. Before applying it, inspect at least:

- `.git/hooks`, `.github/workflows`, and other CI files
- editor tasks and shell startup files
- package-manager lifecycle scripts and lockfile changes
- symlinks and generated binaries
- agent configuration and extension files

## References

- [Pi containerization](https://pi.dev/docs/latest/containerization)
- [Run Pi in OpenShell](https://docs.nvidia.com/openshell/tutorials/run-pi)
- [OpenShell policy schema](https://docs.nvidia.com/openshell/reference/policy-schema)
- [OpenShell security best practices](https://docs.nvidia.com/openshell/security/best-practices)
