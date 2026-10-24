# Spec Delta

## MODIFIED Requirements

### Requirement: Report contents

The report SHALL include the project, harness, image, volume, workspace mode (`mount` or `clone`) and, in clone mode, the workspace volume, egress mode and whether it came from the environment or the default, the env file path, the network (or "per-run isolated internal network" for restricted modes), the policy (`baseline`, `private`, `reasons`, empty `grants`), and whether provider keys enter the agent (false only in strict mode). `rapunzel --config` SHALL always print JSON; `rapunzel-ctl config` follows the controller's output format.

#### Scenario: Text on a terminal
- **WHEN** the user runs `rapunzel-ctl config .` in a terminal
- **THEN** the report is printed as escaped text lines

#### Scenario: Strict mode
- **WHEN** the mode is strict
- **THEN** `providerKeysEnterAgent` is false

#### Scenario: Clone mode
- **WHEN** `RAPUNZEL_WORKSPACE=clone` is set
- **THEN** the report shows `workspace: "clone"` and the workspace volume name
