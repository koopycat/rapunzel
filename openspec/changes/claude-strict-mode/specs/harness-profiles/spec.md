# Spec Delta

## MODIFIED Requirements

### Requirement: Strict mode support is declared per profile

The launcher SHALL refuse `RAPUNZEL_EGRESS=strict` with status 2 for a profile with `H_STRICT_SUPPORTED=false`. Currently pi, opencode, and claude support strict mode; codex and dsh do not.

#### Scenario: Codex in strict mode
- **WHEN** the user runs `RAPUNZEL_EGRESS=strict rapunzel-codex .`
- **THEN** the launcher exits with status 2 and suggests allowlist

#### Scenario: Claude Code in strict mode
- **WHEN** the user runs `RAPUNZEL_EGRESS=strict rapunzel-claude .` with `ANTHROPIC_API_KEY` set
- **THEN** the launcher starts the credential gateway and Claude Code
