# Spec Delta

## MODIFIED Requirements

### Requirement: SNI-verified HTTPS only

The Pipelock config SHALL use strict mode with enforcement on, `forward_proxy.sni_verification: true`, `sni_require_tls: true`, a 900-second idle timeout for long model streams, metrics on `127.0.0.1` only, and JSON logs that include blocked but not allowed events. When the pinned Pipelock release offers it, the config SHALL also refuse ClientHellos that carry the Encrypted Client Hello or ESNI extension. The agent SHALL receive `HTTPS_PROXY` and `https_proxy` pointing at the sidecar and `NODE_USE_ENV_PROXY=1`, and MUST NOT receive `HTTP_PROXY`, so cleartext requests fail closed.

#### Scenario: Domain fronting on a shared CDN
- **WHEN** the agent opens a CONNECT tunnel to an allowed host and sends a ClientHello naming another site
- **THEN** the proxy refuses the tunnel

#### Scenario: Plain HTTP
- **WHEN** the agent requests `http://api.openai.com/`
- **THEN** the request fails, because there is no HTTP proxy and no direct route

#### Scenario: Plaintext through a tunnel
- **WHEN** the agent opens a CONNECT tunnel to an allowed host and sends no TLS
- **THEN** the proxy refuses it

#### Scenario: Encrypted Client Hello
- **WHEN** the pinned Pipelock supports ECH refusal and the agent sends a ClientHello with the ECH extension and an allowed outer server name
- **THEN** the proxy refuses the tunnel
