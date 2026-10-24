# Proposal

## Why

Residual risk 3 in `docs/architecture.md`: with Encrypted Client Hello, the agent's TLS client can put an allowed host in the outer server name and another site on the same CDN in the encrypted inner one. Pipelock's SNI check (3.7.1, `internal/proxy/sni.go`) reads only the plain `server_name` extension, so such a handshake passes. Most default allowed hosts (`api.anthropic.com`, `api.openai.com`) sit behind a CDN that supports ECH.
The agent controls its own TLS client, so turning ECH off on the client side does not help; the proxy has to refuse it. No Pipelock setting does that today.

## What Changes

- `verify-egress.sh allowlist` gains a probe that sends a ClientHello carrying the ECH extension (type `0xfe0d`) with an allowed outer server name through a tunnel, and records whether the proxy forwards it.
- Until the pinned proxy can refuse ECH, the probe reports the gap as a warning naming risk 3 and does not fail the run; the docs mark the risk as confirmed at the proxy instead of "unverified".
- Pipelock is not modified. If a future Pipelock release offers ECH refusal on its own, enabling it and making the probe a hard failure is a separate change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `egress-allowlist`: the SNI requirement adds refusing ClientHellos that carry ECH, effective once the pinned proxy supports it.
- `verification-and-release`: the allowlist check covers ECH.

## Impact

- `lib/egress-probe.mjs` (raw ClientHello with chosen extensions), `verify-egress.sh`.
- `docs/egress.md` (new decision record, risk 3), `docs/architecture.md` (risk 3).
