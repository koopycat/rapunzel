# Proposal

## Why

Four gaps found while hardening rapunzel, implemented on `feat/hardening` (PR #18) before the specs existed and recorded here afterwards:

- The read-only `.git/config` and `.git/hooks` sub-mounts move with their parent, so the agent can `mv .git .git-moved`, create a fresh `.git` with its own hooks, and the host's git runs them. A symlinked config or hooks entry is silently left unmounted and dangles in the container, where the agent can replace it.
- pi ships no shrinkwrap, so every image build resolves pi's transitive dependencies afresh; a newly published malicious version would land in the next build.
- `strict` mode serves only Anthropic, OpenAI, and a custom provider, so users of the other providers pi supports must fall back to `allowlist` and hand the agent their key.
- `strict` mode reaches nothing but the model API, so a task that installs packages or clones a repository forces the choice between that and `allowlist` with the real key in the agent.

## What Changes

- The launcher mounts `.git` onto its own path before the read-only sub-mounts; a mount point cannot be renamed, so `.git` cannot be swapped. A symlinked `.git/config` or `.git/hooks` stops the launch instead of being skipped. **BREAKING** for projects with such a symlink.
- pi and its whole dependency tree install from `profiles/pi/package.json` and `profiles/pi/package-lock.json` with `npm ci` and integrity hashes; Renovate updates the pin and the lockfile together. **BREAKING**: the `PI_VERSION` build argument is gone.
- The strict gateway serves a fixed table of built-in providers: `anthropic`, `openai`, `openrouter`, `google`, `groq`, `mistral`, `deepseek`, `xai`, each from its key variable. Every route also overwrites `X-Goog-Api-Key` and drops a `key` query parameter. In `allowlist` mode each of these keys adds its provider's API host.
- In `strict` mode, `RAPUNZEL_EGRESS_ALLOW` starts Pipelock next to the gateway with the allowlist configuration and gives the agent `HTTPS_PROXY` for tools; an entry that equals or covers a provider API host stops the launch.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `host-file-protection`: `.git` is pinned, and a symlinked git control path stops the launch.
- `egress-strict`: the gateway's route table covers eight built-in providers, routes overwrite every credential header and drop `?key=`, and strict mode accepts a tool allowlist that must not cover a provider host.
- `egress-allowlist`: every built-in provider key adds its API host.
- `egress-modes`: strict mode with a tool allowlist runs two sidecars, both labeled, swept, and removed like any egress resource.
- `environment-filtering`: all built-in provider keys are consumed by the strict gateway; strict mode with a tool allowlist sets its own proxy names.
- `harness-configuration`: pi's strict overrides cover every gateway provider.
- `verification-and-release`: the host-file and egress checks cover the new behavior, pi installs from its lockfile, and Renovate updates pi through it.

## Impact

- `lib/host-files.sh`, `rapunzel`, `lib/egress.sh` (`GATEWAY_BUILTINS`, `gateway_own_sidecar`), `lib/policy.sh` (`policy_refuse_provider_hosts`), `profiles/pi/bootstrap.mjs`, `profiles/pi/package.json`, `profiles/pi/package-lock.json`, `Dockerfile`, `renovate.json`.
- `verify-host-files.sh`, `verify-egress.sh` (`strict-tools` mode), `lib/egress-probe.mjs`, `test-control.sh`, `test.sh`.
- `AGENTS.md`, `docs/architecture.md`, `docs/egress.md` (D17), `docs/guide.md`.
- Strict-mode routes for the six new providers are checked by rendering and against the upstream paths, not with real keys.
