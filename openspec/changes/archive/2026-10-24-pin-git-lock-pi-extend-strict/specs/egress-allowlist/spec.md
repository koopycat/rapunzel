## MODIFIED Requirements

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
