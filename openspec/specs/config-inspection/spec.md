# config-inspection Specification

## Purpose

Users can check what a run would do before starting it: which egress mode applies, which hosts would be allowed and why, and which credentials are present, without starting containers or revealing secret values. Sources: `rapunzel` (`--config`), `lib/policy.sh`, `rapunzel-ctl config`.

## Requirements

### Requirement: Same policy construction as a real run

`rapunzel --config [PROJECT_DIR]` and `rapunzel-ctl config [PROJECT_DIR] [--harness NAME]` SHALL compute the startup allowlist and its reasons with the launcher's own policy code, and SHALL run without contacting Docker, building images, creating volumes, registering a run, or writing the filtered env file. Errors in settings and host lists (invalid hosts or base URLs, incompatible settings, unknown logins, invalid variable names) MUST stop the report too. Checks that run only when the sidecar is configured, such as an empty allowlist or a strict run without a gateway route, are not part of the report.

#### Scenario: Preview an allowlist session
- **WHEN** the user runs `RAPUNZEL_EGRESS=allowlist rapunzel-ctl config . --harness opencode`
- **THEN** the report lists the hosts with reasons such as `api.openai.com: OPENAI_API_KEY present`

#### Scenario: Invalid extra host
- **WHEN** `RAPUNZEL_EGRESS_ALLOW` contains an IP literal
- **THEN** the config command fails just as the launcher would

### Requirement: Report contents

The report SHALL include the project, harness, image, volume, workspace mode (`mount` or `clone`) and, in clone mode, the workspace volume, the agent container's process and memory limits (memory `null` when unset), egress mode and whether it came from the environment or the default, the env file path, the network (or "per-run isolated internal network" for restricted modes), the policy (`baseline`, `private`, `reasons`, empty `grants`), and whether provider keys enter the agent (false only in strict mode). `rapunzel --config` SHALL always print JSON; `rapunzel-ctl config` follows the controller's output format.

#### Scenario: Text on a terminal
- **WHEN** the user runs `rapunzel-ctl config .` in a terminal
- **THEN** the report is printed as escaped text lines

#### Scenario: Strict mode
- **WHEN** the mode is strict
- **THEN** `providerKeysEnterAgent` is false

#### Scenario: Default limits
- **WHEN** no limit variables are set
- **THEN** the report shows a process limit of 4096 and a memory limit of `null`

#### Scenario: Clone mode
- **WHEN** `RAPUNZEL_WORKSPACE=clone` is set
- **THEN** the report shows `workspace: "clone"` and the workspace volume name

### Requirement: Credential presence without values

The report SHALL list each present credential (allowlisted or gateway-consumed names containing `KEY` or `TOKEN`, plus the named key variable) with its source, `environment` or `env-file`. It MUST NOT include credential values or custom URL paths, and MUST state that OAuth state is not inspected.

#### Scenario: Key from the env file
- **WHEN** `ANTHROPIC_API_KEY` is set only in the env file
- **THEN** the report lists `{name: "ANTHROPIC_API_KEY", present: true, source: "env-file"}` and no value

#### Scenario: Secret never printed
- **WHEN** `OPENAI_API_KEY=secret-env` is set
- **THEN** the string `secret-env` appears nowhere in the output
