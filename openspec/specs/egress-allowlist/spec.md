# egress-allowlist Specification

## Purpose

In `allowlist` mode the agent reaches only named hosts over HTTPS, through a Pipelock CONNECT proxy that checks the TLS server name and refuses private destinations. The allowlist comes only from host-side settings, so the agent cannot widen it. Sources: `lib/egress.sh`, `lib/policy.sh`, `lib/control.jq`, `docs/egress.md` (D4, D7, D10–D12).

## Requirements

### Requirement: Allowlist built from host settings only

The startup allowlist SHALL be the union of: the profile's `H_EGRESS_HOSTS`; the API host of each built-in provider whose key is set (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, the same table the strict gateway uses); the custom base URL's host; each `RAPUNZEL_EGRESS_LOGINS` entry's hosts; `RAPUNZEL_EGRESS_ALLOW`; and `RAPUNZEL_EGRESS_ALLOW_PRIVATE`, each recorded with its reason. It MUST NOT come from `auth.json` or other agent-writable state, and an empty allowlist MUST stop the launcher.

#### Scenario: API key adds its provider
- **WHEN** allowlist mode runs with only `OPENAI_API_KEY` set
- **THEN** the allowlist is exactly `api.openai.com`, with reason `OPENAI_API_KEY present`

#### Scenario: Further provider key
- **WHEN** allowlist mode runs with only `GROQ_API_KEY` set
- **THEN** the allowlist is exactly `api.groq.com`, with reason `GROQ_API_KEY present`

#### Scenario: Agent edits auth.json
- **WHEN** the agent adds a provider login to `auth.json` in the volume
- **THEN** the next run's allowlist is unchanged

#### Scenario: Nothing configured
- **WHEN** allowlist mode runs with no keys, URL, logins, or extra hosts
- **THEN** the launcher lists the settings that add hosts and does not start

### Requirement: Host name grammar

Every allowlist entry SHALL be lowercased and validated by one grammar shared with runtime grants and event parsing: DNS labels of letters, digits, and inner hyphens, at least two labels, a top-level label starting with a letter, labels of at most 63 and names of at most 253 characters. A leading `*.` is accepted only for startup entries. Invalid values MUST be rejected without echoing them.

#### Scenario: IP literal
- **WHEN** `RAPUNZEL_EGRESS_ALLOW=10.0.0.5`
- **THEN** the launcher fails with a redacted "not an allowable DNS host name" message

#### Scenario: Wildcard entry
- **WHEN** `RAPUNZEL_EGRESS_ALLOW=*.example.com`
- **THEN** Pipelock receives `*.example.com` unchanged, and the controller treats both `example.com` and `api.example.com` as covered by startup policy

### Requirement: Custom base URL host

The custom base URL SHALL be an `http(s)` URL without credentials, query, or fragment, and its host is added to the allowlist. Any other form MUST stop the launcher with a redacted error.

#### Scenario: URL with credentials
- **WHEN** `RAPUNZEL_API_BASE_URL=https://user:pw@router.example/v1`
- **THEN** the launcher refuses it without printing the value

### Requirement: Named login providers

`RAPUNZEL_EGRESS_LOGINS` SHALL accept only these names, each expanding to fixed hosts: `openai` → `api.openai.com`, `auth.openai.com`; `openai-codex` → `chatgpt.com`, `auth.openai.com`; `anthropic` → `api.anthropic.com`, `platform.claude.com`; `github-copilot` → `api.github.com`, `*.githubcopilot.com`. An unknown name MUST stop the launcher.

#### Scenario: Claude subscription
- **WHEN** `RAPUNZEL_EGRESS_LOGINS=anthropic`
- **THEN** `api.anthropic.com` and `platform.claude.com` are allowed

### Requirement: Private destinations only by exact name

Pipelock SHALL refuse private, loopback, link-local, and metadata addresses after resolving names itself. Only exact names in `RAPUNZEL_EGRESS_ALLOW_PRIVATE` SHALL be trusted to resolve privately, by adding them to both the allowlist and `trusted_domains`; wildcards MUST be refused. No other source, including runtime grants, may add `trusted_domains`.

#### Scenario: LAN model router
- **WHEN** `RAPUNZEL_EGRESS_ALLOW_PRIVATE=router.lan` and `router.lan` resolves to `10.0.0.5`
- **THEN** the agent reaches `router.lan` through the proxy

#### Scenario: Allowlisted name pointed at the LAN
- **WHEN** an allowed public name resolves to `192.168.1.1`
- **THEN** the proxy refuses the tunnel

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

### Requirement: Package registries and GitHub are not allowed by default

No package registry or GitHub host SHALL be on the allowlist unless the user adds it, because those hosts accept uploads with any token. The only built-in exception is the `github-copilot` login, which needs `api.github.com`.

#### Scenario: npm install in allowlist mode
- **WHEN** the agent runs `npm install` with only provider keys configured
- **THEN** the connection to `registry.npmjs.org` is refused

### Requirement: No request rate limit on the allowlist proxy

The Pipelock config SHALL set `fetch_proxy.monitoring.max_requests_per_minute` to 1,000,000, because Pipelock treats 0 as its default of 60 per host and minute and has no off switch. A local agent MUST NOT get `429` for opening many tunnels to an allowed host, since the limit counts tunnels, not data, and so does not bound exfiltration.

#### Scenario: Burst of tunnels to an allowed host
- **WHEN** the agent opens 70 CONNECT tunnels to an allowed host within a minute
- **THEN** none of them is answered with `429`

#### Scenario: Rendered config
- **WHEN** the launcher renders the Pipelock config for an allowlist run
- **THEN** it contains `max_requests_per_minute: 1000000` under `fetch_proxy.monitoring`
