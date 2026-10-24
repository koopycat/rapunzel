# Spec Delta

## MODIFIED Requirements

### Requirement: Boundary checks

The egress, host-file, and controller checks SHALL exercise the launcher's actual configuration through `rapunzel --exec` rather than a copy of it; `test.sh` and `verify-isolation.sh` run the image directly with equivalent user, capability, and mount options. Together the checks SHALL cover:

| Script | Proves | Network |
|---|---|---|
| `test.sh` | The harness starts through the real entrypoint, the identity maps to `agent`, configuration is written, `HOME` is writable by the caller's UID, a TypeScript extension loads through pi's jiti loader | none |
| `test-control.sh` | Config inspection never calls Docker and leaks no secret; registry ownership and symlink checks; grant and event host grammar; sanitized, grouped block events; prefix resolution; safe text and JSON rendering; log-read failures are errors | none, no Docker |
| `verify-isolation.sh` | Not root; `/workspace` and the volume are writable; host paths are invisible; no host home mount | none |
| `verify-host-files.sh` | Git hook/config/`core.hooksPath` writes fail; a commit works; planted files are reported | none |
| `verify-workspace.sh` | Clone mode has no host bind mount; host commits arrive as `origin/*` without touching agent branches; agent commits arrive on the host only under `refs/remotes/rapunzel-<harness>/*`; planted hooks, config, and tags stay in the workspace; host-executed paths in new commits are reported | none |
| `verify-egress.sh strict` | No external DNS, direct IP, metadata, or host access; upstream only through the gateway; unknown routes 403; the real key never reaches the agent; the agent's own credentials are replaced | none |
| `verify-egress.sh allowlist` | The same network checks; allowed host works; other hosts, IP literals, wrong or missing SNI, plaintext tunnels, and plain HTTP are refused; private hosts need `RAPUNZEL_EGRESS_ALLOW_PRIVATE` | internet |
| `verify-control.sh` | Grants and revocation through the real launcher and pinned Pipelock, TLS binding after reloads, concurrent operators, prefix collisions, log floods not displacing accepted-policy evidence, cleanup when stdout closes mid-transaction | internet |

None of the checks SHALL need provider credentials. A listener on the host network serves as a canary for host reachability.

#### Scenario: Host reachable from the internal network
- **WHEN** a change makes the host canary reachable from a restricted-mode agent
- **THEN** `verify-egress.sh` fails

#### Scenario: Clone mode leaks a hook
- **WHEN** a change lets a hook written in the workspace reach the host repository
- **THEN** `verify-workspace.sh` fails

### Requirement: CI runs every check

`ci.yml` SHALL run on pull requests and as a reusable workflow: shellcheck on every shell script and profile, `node --check` on every bootstrap and helper script, `test-control.sh`, the pi image build and smoke test, the other harness images and their smoke tests when files that go into them changed, and the isolation, host-file, workspace, egress, and controller checks.

#### Scenario: Profile change
- **WHEN** a pull request changes `profiles/codex/bootstrap.mjs`
- **THEN** CI builds and smoke-tests the claude, codex, dsh, and opencode images as well as pi
