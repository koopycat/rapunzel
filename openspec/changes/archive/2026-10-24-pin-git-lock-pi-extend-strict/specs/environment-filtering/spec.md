## MODIFIED Requirements

### Requirement: Egress modes manage proxy and offline names

In `allowlist` mode, `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, and the profile's offline names SHALL NOT be forwarded from the host; the launcher sets its own. In `strict` mode only the profile's `H_ENV_ALLOW_GATEWAY` names SHALL be forwarded, every built-in provider key and the custom provider's settings go to the gateway instead, and with a tool allowlist the launcher sets its own `HTTPS_PROXY` and `NO_PROXY`. Any other allowlisted name set on the host that the gateway does not consume SHALL be reported as not passed; such names from the env file are reported as dropped.

#### Scenario: Host proxy in allowlist mode
- **WHEN** the host sets `HTTP_PROXY=http://corp:3128` and runs in allowlist mode
- **THEN** the container has no `HTTP_PROXY`, and `HTTPS_PROXY` points at the sidecar

#### Scenario: Further provider key in strict mode
- **WHEN** `GEMINI_API_KEY` is set on the host in strict mode
- **THEN** the gateway receives it, the container does not, and the launcher does not warn about it

#### Scenario: Extra key in strict mode
- **WHEN** `HF_TOKEN` is set on the host in strict mode
- **THEN** the launcher warns that it is not passed and the container does not receive it
