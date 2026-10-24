# Spec Delta

## MODIFIED Requirements

### Requirement: Report contents

The report SHALL include the project, harness, image, volume, egress mode and whether it came from the environment or the default, the env file path, the network (or "per-run isolated internal network" for restricted modes), the agent container's process and memory limits (memory `null` when unset), the policy (`baseline`, `private`, `reasons`, empty `grants`), and whether provider keys enter the agent (false only in strict mode). `rapunzel --config` SHALL always print JSON; `rapunzel-ctl config` follows the controller's output format.

#### Scenario: Text on a terminal
- **WHEN** the user runs `rapunzel-ctl config .` in a terminal
- **THEN** the report is printed as escaped text lines

#### Scenario: Strict mode
- **WHEN** the mode is strict
- **THEN** `providerKeysEnterAgent` is false

#### Scenario: Default limits
- **WHEN** no limit variables are set
- **THEN** the report shows a process limit of 4096 and a memory limit of `null`
