# Spec Delta

## ADDED Requirements

### Requirement: No request rate limit on the allowlist proxy

The Pipelock config SHALL set `fetch_proxy.monitoring.max_requests_per_minute` to 1,000,000, because Pipelock treats 0 as its default of 60 per host and minute and has no off switch. A local agent MUST NOT get `429` for opening many tunnels to an allowed host, since the limit counts tunnels, not data, and so does not bound exfiltration.

#### Scenario: Burst of tunnels to an allowed host
- **WHEN** the agent opens 70 CONNECT tunnels to an allowed host within a minute
- **THEN** none of them is answered with `429`

#### Scenario: Rendered config
- **WHEN** the launcher renders the Pipelock config for an allowlist run
- **THEN** it contains `max_requests_per_minute: 1000000` under `fetch_proxy.monitoring`
