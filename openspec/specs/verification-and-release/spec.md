# verification-and-release Specification

## Purpose

Every isolation claim has an automated check that attacks the boundary through the real launcher, and an image is published only after those checks pass. Dependency updates are tracked so the security boundary is never updated unreviewed. Sources: `test.sh`, `test-control.sh`, `verify-*.sh`, `lib/egress-probe.mjs`, `lib/prune-foreign-platforms.mjs`, `Dockerfile`, `.github/workflows/`, `renovate.json`.

## Requirements

### Requirement: Boundary checks

The egress, host-file, and controller checks SHALL exercise the launcher's actual configuration through `rapunzel --exec` rather than a copy of it; `test.sh` and `verify-isolation.sh` run the image directly with equivalent user, capability, and mount options. Together the checks SHALL cover:

| Script | Proves | Network |
|---|---|---|
| `test.sh` | The harness starts through the real entrypoint, the identity maps to `agent`, configuration is written, `HOME` is writable by the caller's UID, a TypeScript extension loads through pi's jiti loader | none |
| `test-control.sh` | Config inspection never calls Docker and leaks no secret; registry ownership and symlink checks; grant and event host grammar; sanitized, grouped block events; prefix resolution; safe text and JSON rendering; log-read failures are errors | none, no Docker |
| `verify-isolation.sh` | Not root; `/workspace` and the volume are writable; host paths are invisible; no host home mount | none |
| `verify-host-files.sh` | Git hook/config/`core.hooksPath` writes fail; a commit works; planted files are reported | none |
| `verify-egress.sh strict` | No external DNS, direct IP, metadata, or host access; upstream only through the gateway; unknown routes 403; the real key never reaches the agent; the agent's own credentials are replaced | none |
| `verify-egress.sh allowlist` | The same network checks; allowed host works; other hosts, IP literals, wrong or missing SNI, plaintext tunnels, and plain HTTP are refused; private hosts need `RAPUNZEL_EGRESS_ALLOW_PRIVATE` | internet |
| `verify-control.sh` | Grants and revocation through the real launcher and pinned Pipelock, TLS binding after reloads, concurrent operators, prefix collisions, log floods not displacing accepted-policy evidence, cleanup when stdout closes mid-transaction | internet |

None of the checks SHALL need provider credentials. A listener on the host network serves as a canary for host reachability.

#### Scenario: Host reachable from the internal network
- **WHEN** a change makes the host canary reachable from a restricted-mode agent
- **THEN** `verify-egress.sh` fails

### Requirement: CI runs every check

`ci.yml` SHALL run on pull requests and as a reusable workflow: shellcheck on every shell script and profile, `node --check` on every bootstrap and helper script, `test-control.sh`, the pi image build and smoke test, the other harness images and their smoke tests when files that go into them changed, and the isolation, host-file, egress, and controller checks.

#### Scenario: Profile change
- **WHEN** a pull request changes `profiles/codex/bootstrap.mjs`
- **THEN** CI builds and smoke-tests the claude, codex, dsh, and opencode images as well as pi

### Requirement: Publishing only after CI

`publish-image.yml` SHALL call `ci.yml` and publish the multi-architecture image (`linux/amd64`, `linux/arm64`) to `ghcr.io/koopycat/rapunzel` only after it passes. `ci.yml` MUST NOT get its own push trigger.

#### Scenario: Failing check on main
- **WHEN** `verify-egress.sh` fails on a push to `main`
- **THEN** no image is published

#### Scenario: Tag release
- **WHEN** a `v*` tag is pushed
- **THEN** the image is tested and published regardless of path filters

### Requirement: Workflow limits and docs-only skips

Both workflows SHALL keep their job timeouts and concurrency groups. They MAY skip docs-only changes with `paths-ignore` only while `main` has no required status checks; the `pull_request` filter in `ci.yml` MUST be dropped before `test` becomes required.

#### Scenario: Docs-only pull request
- **WHEN** a pull request changes only `docs/guide.md`
- **THEN** CI does not run

### Requirement: Image build hygiene

The image SHALL install harness CLIs with `npm install --ignore-scripts`, running only the one install script a harness needs to link its native binary. In the pi stage, `lib/prune-foreign-platforms.mjs` MUST run in the same `RUN` layer as `npm install` and remove packages whose `os`/`cpu` exclude the build platform, because pi ships no shrinkwrap and transitive dependencies resolve at build time. Harness installs are root-owned and are updated by rebuilding, not by self-update.

#### Scenario: Foreign esbuild binaries
- **WHEN** the pi image is built on `linux/arm64`
- **THEN** no `@esbuild/*` package for another platform remains in the image

### Requirement: Dependency update policy

Renovate SHALL track the pinned pi version, the other harness CLI versions, the sidecar image digests, GitHub Action SHAs, and the base image. pi patch updates MAY automerge after CI passes and at least one day of release age; pi minor and major updates, harness CLIs (one weekly group), and the sidecar images (one weekly group) MUST wait for review.

#### Scenario: New Pipelock release
- **WHEN** Pipelock publishes a new image
- **THEN** Renovate opens a PR updating the tag and digest in `lib/egress.sh`, and it is never merged automatically
