# runtime-egress-control Specification

## Purpose

`rapunzel-ctl` lets the operator, from another host terminal, discover live runs, inspect their redacted policy, see blocked destinations, and grant or revoke exact hosts for one running `allowlist` session. Authority lives only in host-side metadata the workload cannot reach, and a change counts as applied only after the live proxy acknowledges it. Sources: `rapunzel-ctl`, `lib/runs.sh`, `lib/control.sh`, `lib/control.jq`, `lib/ctl-output.sh`, `lib/ctl-output.jq`, `docs/egress.md` (D14).

## Requirements

### Requirement: Host-only run registry

Each launcher run SHALL get a random 24-hex-digit run ID, name its agent container `rapunzel-agent-<id>`, label its containers and networks with it, and keep metadata in `<runs root>/<id>/` (`run.json`, `policy.json`, `config.json`, `pipelock.yaml`, `audit.jsonl`). No controller socket, credentials, or Docker socket SHALL enter the workload, and metadata MUST NOT be sourced as shell code. A normal exit SHALL remove the run's directory.

#### Scenario: Normal exit
- **WHEN** a run ends normally
- **THEN** its registry directory, including the operator audit, is gone

### Requirement: Protected registry location

The runs root SHALL be `RAPUNZEL_RUNS_DIR` or `${XDG_STATE_HOME:-~/.local/state}/rapunzel/runs`. It MUST NOT be a symlink, MUST be owned by the caller with mode 0700, MUST lie outside the mounted project, and MUST NOT contain the project.

#### Scenario: Registry inside the project
- **WHEN** the user runs the launcher on their home directory and the runs root is under it
- **THEN** the launcher refuses and asks for `RAPUNZEL_RUNS_DIR` outside the project

#### Scenario: Loose permissions
- **WHEN** the runs root has mode 0755
- **THEN** the launcher and controller refuse to use it

### Requirement: Run published only when ready

The launcher SHALL mark a run `running` and print its ID only after the egress sidecar is up. In `allowlist` mode it MUST record the policy hash from the proxy's startup event and fail if none is reported.

#### Scenario: Startup hash recorded
- **WHEN** an allowlist run starts
- **THEN** `run.json` has `status: "running"` and a 64-hex `policyHash` from Pipelock's startup log

### Requirement: Safe run selection

Selectors SHALL be a full ID or a unique 8–24-character lowercase hex prefix among the caller's registry directories; stale and foreign-daemon records count toward ambiguity. Selection MUST freeze the full ID. The controller MUST NOT pick the newest run or infer a run from the working directory.

#### Scenario: Run ended normally
- **WHEN** the run's launcher exited and removed its record
- **THEN** the controller reports that no registry run matches and the run may have ended

#### Scenario: Ambiguous prefix
- **WHEN** two registry records start with `a1b2c3d4`
- **THEN** the controller refuses and asks for a full ID

### Requirement: Selected run is verified live

After resolving a selector, the controller MUST verify that `run.json` names the same run, agent, and current Docker daemon with `status: "running"`, that the agent container is running with the matching `rapunzel.run` label, and, for restricted runs, that the sidecar carries the matching label.

#### Scenario: Run on another daemon
- **WHEN** the record was created against a different Docker daemon
- **THEN** the controller refuses it

#### Scenario: Stale record
- **WHEN** a killed launcher left its record behind and the agent container is gone
- **THEN** the controller reports that the run is no longer active

### Requirement: Discovery and inspection

`runs` SHALL list only verified registry-backed live agents on the selected daemon, not arbitrary labeled containers or stale records. `inspect` SHALL show the run's project, harness, egress mode, image, volume, startup policy, grants, private trust, allowance reasons, whether provider keys enter the agent, credential names and sources (never values), and whether policy is uncertain.

#### Scenario: Stale record after SIGKILL
- **WHEN** a killed launcher left its run directory behind
- **THEN** `runs` does not list it

### Requirement: Safe output

The controller SHALL print text on a terminal and JSON otherwise, overridable with a leading `--json` or `--format=text|json|auto`. Both formats MUST ASCII-escape untrusted strings, progress messages MUST go only to a terminal stderr, and raw log messages, headers, URL paths, and invalid host names MUST NOT be printed.

#### Scenario: Hostile destination name in logs
- **WHEN** a blocked event's target contains terminal escape sequences
- **THEN** the output shows `[invalid target redacted]`

### Requirement: Blocked-event views

`egress pending RUN` SHALL group blocked and SNI-mismatch events from at most the last 2,000 retained sidecar log lines by host into a `schemaVersion: 1` object with ports, event counts, first and last times, kinds, startup/runtime/not-covered coverage, and private trust. Coverage SHALL be `unknown` while an update is locked or uncertain. `egress watch RUN` SHALL stream the same sanitized events, history first. A failed log read MUST be an error, not an empty result.

#### Scenario: Policy update in progress
- **WHEN** another operator holds the update lock
- **THEN** every destination's coverage is `unknown` and none is an approval candidate

### Requirement: Approval candidates

Only allowlist CONNECT blocks of valid hosts that are not covered by startup or runtime policy SHALL be approval candidates. TLS/SNI violations, address protection, and DNS failures MUST be diagnostic only, and a host with any such event is not a candidate.

#### Scenario: Missing registry host
- **WHEN** the agent's `npm install` was blocked for `registry.npmjs.org`
- **THEN** `pending` lists that host as not covered and an approval candidate

#### Scenario: SNI mismatch
- **WHEN** a tunnel was refused for an SNI mismatch
- **THEN** its host is shown with kind `TLS/SNI violation` and is not an approval candidate

### Requirement: Exact, per-run grants

`egress allow|revoke RUN HOST` SHALL work only for `allowlist` runs, on the originating host and selected daemon. HOST MUST be an exact DNS name in the shared grammar, with no wildcard, URL, IP literal, or port. A host already covered by the startup policy, including by a startup wildcard, MUST be refused.

#### Scenario: Wildcard grant
- **WHEN** the operator runs `egress allow <id> '*.npmjs.org'`
- **THEN** the controller exits with status 2

#### Scenario: Host covered at startup
- **WHEN** the startup policy allows `*.example.com` and the operator revokes `api.example.com`
- **THEN** the controller refuses, because runtime grants cannot override startup policy

#### Scenario: Strict-mode run
- **WHEN** the operator runs `egress allow` on a strict run
- **THEN** the controller exits with status 2

### Requirement: Grant scope

Grants SHALL last until revoked or the run ends, MUST NOT persist to later runs or add private-address trust, and do not hold or replay the blocked request. Revoke SHALL remove only controller-added grants and affect only new tunnels. Re-granting an existing grant or revoking a missing one SHALL report no change.

#### Scenario: Grant then retry
- **WHEN** the operator runs `rapunzel-ctl egress allow <id> registry.npmjs.org` and the agent retries
- **THEN** the retry can reach `registry.npmjs.org`, and the output says the agent must retry and startup policy and private-address protections are unchanged

#### Scenario: Granted host resolves privately
- **WHEN** a granted host resolves to a private address and was not trusted at startup
- **THEN** the proxy still refuses it

#### Scenario: Revoke with an open tunnel
- **WHEN** the operator revokes a grant while the agent has a tunnel open to that host
- **THEN** new tunnels are refused and the open one is not closed

### Requirement: Confirmed policy transactions

A mutation SHALL stage candidate and previous configs in the sidecar's config volume, mark the run uncertain, atomically rename the candidate in place with a networkless, capability-free helper from the agent's immutable image ID, and send SIGHUP. Success MUST require a reload-success event carrying the candidate hash after a daemon-clock fence. Only then SHALL metadata be updated, uncertainty cleared, and an audit line appended.

#### Scenario: Old acknowledgement
- **WHEN** the same hash was accepted earlier in the run
- **THEN** that earlier event does not confirm the new reload, because it predates the fence

#### Scenario: Reload not confirmed
- **WHEN** no matching reload event appears within the wait
- **THEN** the controller restores the previous config, confirms its hash after a new fence, clears uncertainty, and reports that the previous policy was restored

#### Scenario: Rollback not confirmed
- **WHEN** rollback cannot be confirmed either
- **THEN** the controller stops the sidecar, verifies it stopped, and otherwise reports that egress shutdown could not be confirmed; further mutations are refused until the run restarts

#### Scenario: Interrupted controller
- **WHEN** the controller receives SIGTERM after replacing the config
- **THEN** its own exit handler removes the validator, attempts the uncertain-state shutdown, and releases the lock

### Requirement: Transaction preconditions

Before changing anything, a mutation SHALL take a per-run host lock, which is never reaped automatically, and check that the sidecar runs, no earlier update is uncertain, and the latest accepted hash in all retained sidecar logs (not the bounded diagnostic window) equals the recorded `policyHash`.

#### Scenario: Concurrent update
- **WHEN** a second `egress allow` starts while one holds the lock
- **THEN** it exits saying the update is locked

#### Scenario: Logs rotated away
- **WHEN** no accepted-policy evidence remains in the sidecar logs
- **THEN** the update is refused before anything changes

### Requirement: Candidate validation

The controller SHALL render the candidate config and compute its normalized hash with a networkless, read-only, capability-free instance of the running sidecar's image that mounts only the sidecar's config volume. A candidate the validator rejects MUST leave the live policy unchanged.

#### Scenario: Invalid candidate
- **WHEN** the validator never reports a startup hash for the candidate
- **THEN** the controller reports that validation failed and the live policy is unchanged
