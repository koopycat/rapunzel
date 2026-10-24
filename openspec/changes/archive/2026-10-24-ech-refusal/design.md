# Design

## Context

`verify-egress.sh allowlist` already proves that a tunnel whose SNI differs from the CONNECT host, or has none, gets no upstream response (`lib/egress-probe.mjs`, `tlsThroughTunnel`, `noUpstreamResponse`). Node's TLS client cannot send an ECH extension, so the probe needs a hand-built ClientHello. Pipelock 3.7.1 peeks the first record, parses extensions until `server_name`, and compares; other extensions are ignored.

## Goals / Non-Goals

**Goals:**
- Measure, in CI, whether the proxy forwards an ECH-bearing ClientHello with an allowed outer name.
- Keep the gap visible in CI and the docs until the pinned Pipelock can refuse ECH, keeping rapunzel's no-CA design.

**Non-Goals:**
- Proving that a given CDN routes on the inner name; the proxy must not depend on CDN behavior.
- TLS interception or a CA in the agent.
- Modifying, forking, or patching Pipelock.
- A rapunzel-owned TLS filter in front of Pipelock (D-record in `docs/egress.md` already weighs a purpose-built guard; one more sidecar is not worth it while upstream is active and releases often).

## Decisions

**Hand-built ClientHello in the probe.**
A minimal TLS 1.3 ClientHello with `server_name` set to the allowed host, `supported_versions`, `key_share` (random X25519 bytes), and an `encrypted_client_hello` extension (`0xfe0d`) with outer type, a random config ID, and random payload. The probe opens the CONNECT tunnel, writes the record, and classifies the result like the SNI probes: any upstream byte means forwarded. The local TLS upstream used for private-host checks answers with an alert or ServerHello either way, so the result does not depend on the internet.

**Warning now, failure later.**
The probe's verdict depends on a capability flag in `verify-egress.sh` set from the pinned proxy version. While the flag is off, a forwarded ECH hello prints `known gap (risk 3): proxy forwards Encrypted Client Hello` and counts as passed; a refusal fails the run as a surprise worth investigating. When the flag is on, forwarding fails the run.

**If Pipelock ever refuses ECH.**
Should a Pipelock release offer an ECH refusal setting, turning it on goes through the reviewed sidecar update (Renovate group or manual digest pin) in a separate change that sets the key, flips the capability flag, and closes risk 3.

## Risks / Trade-offs

- [No Pipelock release refuses ECH] → The gap stays documented and reported by CI; a purpose-built guard (the D4 fallback in `docs/egress.md`) would be a separate decision.
- [Clients that send ECH GREASE] → GREASE ECH uses the same extension type, so a client with GREASE on would be refused once the setting is active. Node, curl, and Go do not send ECH GREASE by default; the probe documents this, and the release check of each harness image catches a harness that does.
- [The hand-built hello is malformed and refused for that reason] → The probe first sends the same hello without the ECH extension and requires it to be forwarded, so a refusal can only come from the extension.
