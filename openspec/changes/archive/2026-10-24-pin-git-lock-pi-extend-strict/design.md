# Design

## Context

This change records work already implemented on `feat/hardening` and rebased onto the clone workspace, Claude Code strict mode, and ECH changes. See proposal.md for the gaps it closes.
Mount mode protects git through nested read-only bind mounts (`lib/host-files.sh`); clone mode needs none and is unaffected.
The strict gateway rendered fixed routes for Anthropic, OpenAI, and a custom provider, each case written out by hand in `gateway_configure`, and the allowlist hard-coded the same two hosts in `lib/policy.sh`.

## Goals / Non-Goals

**Goals:**
- Close the `.git` swap without giving up commits from inside the container.
- Make a pi image build reproducible down to every transitive package.
- Keep every provider key pi supports out of the agent in strict mode, through one table that cannot drift between routes, env filtering, and the allowlist.
- Let strict mode reach package registries and git hosts without weakening the key guarantee.

**Non-Goals:**
- Lockfiles for the other harness CLIs.
- Runtime grants (`rapunzel-ctl egress allow`) in strict mode; tool hosts are fixed at startup.
- `RAPUNZEL_EGRESS_LOGINS` or `RAPUNZEL_EGRESS_ALLOW_PRIVATE` in strict mode.
- opencode and Claude Code routes for the new providers; their bootstraps keep their current providers.

## Decisions

**Pin `.git` with a bind mount onto itself.**
A mount point cannot be renamed (`EBUSY`), so mounting `.git` over its own path before the read-only parts stops `mv .git`. The sub-mounts alone do not, because they move with their parent.
Alternative: hash `.git/config` and hooks after the run and restore them. Rejected: it detects after the agent's hooks could already have run on a host `git` call during the session.
Alternative: skip a symlinked config or hooks entry, as before. Rejected: the dangling target can be created inside the container and the host's git then uses it.

**Lockfile under `profiles/pi`, installed with `npm ci`.**
pi ships no shrinkwrap, so the lockfile has to be ours. It was resolved with `--before` pi 1.4.0's release, so no package is newer than pi itself. `npm ci` refuses a tree that disagrees with the lockfile, which is why the `PI_VERSION` build argument goes away.
Alternative: `npm install -g` with `--before`. Rejected: no integrity hashes and no reviewable diff when dependencies change.

**One provider table, `GATEWAY_BUILTINS` in `lib/egress.sh`.**
Each row names the provider id (pi's, also the route), the key variable, the upstream origin, an optional path prefix, and the auth style. The table drives the gateway routes, the gateway env file, the names the strict env filter consumes, the allowlist hosts, and the error listing accepted keys, so adding a provider is one line.
OpenRouter takes two prefixes because pi uses `/api` for its Anthropic Messages models and `/api/v1` for the rest; `/v1/*` goes to `/api`, everything else to `/api/v1`.
The Anthropic row keeps the subscription-token fallback from the Claude Code change: an API key wins, otherwise `CLAUDE_CODE_OAUTH_TOKEN` feeds the same route as `Authorization: Bearer` (D15).

**Every route clears every credential.**
Each route removes `Authorization`, `X-Api-Key`, and `X-Goog-Api-Key` except the one it sets, and drops a `key` query parameter, because Google accepts a key in the query. Caddy applies deletions after sets, so a style deletes only headers it does not set.

**Pipelock next to Caddy for tools (D17).**
With `RAPUNZEL_EGRESS_ALLOW` in strict mode, the launcher starts Pipelock with the allowlist configuration beside the gateway. Model traffic is plain `http://llm-proxy:8080`, which `HTTPS_PROXY` never covers; `NO_PROXY=llm-proxy` makes that explicit for clients that also proxy HTTP.
Pipelock stays `EGRESS_SIDECAR`, the container run metadata and `rapunzel-ctl` read; the gateway gets `rapunzel-gateway-<run>`. Plain strict mode keeps its single container name.
Alternative: a second, separate forward proxy. Rejected: stock Caddy has no forward proxy, and Pipelock with the allowlist configuration is already pinned and checked by `verify-egress.sh`, including SNI verification.
An entry that covers a provider host is refused, because through Pipelock the agent could talk to that provider with a key of its own.

**Decision record numbering.**
`main` already used D15 (Claude Code through the gateway) and D16 (ECH), so the tool allowlist record is D17.

## Risks / Trade-offs

- [The six new routes have not run with real keys] → `test-control.sh` checks the rendering offline, the upstream paths were confirmed to exist (401/403 without a key, 200 for OpenRouter's public model list), and the commit was checked against the pinned Caddy with attacker credentials in every header and the query.
- [A compromised version already in the lockfile] → It stays until noticed; Renovate PRs show lockfile diffs for review.
- [`.git` bind mount is one more nested mount] → Docker Desktop's VM shut down with the existing nested mounts; Colima and Linux are unaffected, and clone mode avoids all of them.
- [A tool host is a path out for whatever the agent reads] → As in allowlist mode (residual risk 2); only the provider key stays out.
- [Projects with a symlinked `.git/hooks` stop launching] → The error names the path and asks for a real directory.

## Migration Plan

- Users passing `--build-arg PI_VERSION` drop it; the version comes from `profiles/pi/package.json`.
- A project with a symlinked `.git/config` or `.git/hooks` replaces the link with a regular file or directory, or uses `--clone`.
- Rollback is reverting the PR; no state in volumes depends on it, and the pi bootstrap removes gateway overrides outside strict mode.
