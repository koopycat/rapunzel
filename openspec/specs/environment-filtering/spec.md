# environment-filtering Specification

## Purpose

The container never inherits the host environment. Only allowlisted names enter it, from the host environment or a filtered env file, so neither the host nor a mistaken env file can leak unrelated secrets or inject loader and interpreter hooks. Secrets reach the container only at runtime. Sources: `rapunzel`, `profiles/<name>/profile.sh`.

## Requirements

### Requirement: Allowlist with a winning denylist

A variable SHALL enter the container only if its name is on the allowlist: the shared provider keys (such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `HF_TOKEN`), `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`, the profile's `H_ENV_ALLOW`, and the name in `RAPUNZEL_API_KEY_VARIABLE`. Allowed host variables SHALL be forwarded by name only, so their values never appear on the Docker command line.

#### Scenario: Unrelated host secret
- **WHEN** `AWS_SECRET_ACCESS_KEY` is set on the host
- **THEN** it is not present in the container

### Requirement: Denylist wins

A denied name MUST NOT enter the container even when it is allowlisted or named as the key variable: `BASH_ENV`, `ENV`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`, `NODE_OPTIONS`, `PYTHONSTARTUP`, `PERL5OPT`, `RUBYOPT`, `HOME`, `PATH`, `TMPDIR`, `RAPUNZEL_STATE_DIR`, the profile's `H_STATE_ENV`, and the profile's `H_ENV_DENY`.

#### Scenario: Loader hook in the env file
- **WHEN** the env file sets `LD_PRELOAD=/workspace/evil.so`
- **THEN** the variable is dropped and reported

#### Scenario: State directory redirect
- **WHEN** the host sets `PI_CODING_AGENT_DIR=/workspace/.pi`
- **THEN** pi still uses `/home/agent/.pi/agent`

### Requirement: Env file selection

The launcher SHALL read provider settings from `RAPUNZEL_ENV_FILE`, defaulting to `${XDG_CONFIG_HOME:-~/.config}/rapunzel/<harness>.env` when that file exists; an empty `RAPUNZEL_ENV_FILE` opts out. A named file that does not exist MUST stop the launcher with status 1. A file whose mode (after following symlinks) is not 600 SHALL produce a warning.

#### Scenario: Default env file
- **WHEN** `~/.config/rapunzel/claude.env` exists and `RAPUNZEL_ENV_FILE` is unset
- **THEN** `rapunzel-claude` uses it and says so on stderr

#### Scenario: World-readable env file
- **WHEN** the env file has mode 644
- **THEN** the launcher warns and suggests `chmod 600`

### Requirement: Env file filtering

Env file lines SHALL be filtered through the same allowlist and denylist into a mode-0600 temporary file that is deleted on exit. Comments and blank lines SHALL be skipped, malformed lines ignored with a redacted warning, and dropped names reported by name only.

#### Scenario: Malformed line with a secret
- **WHEN** the env file contains `export OPENAI_API_KEY sk-123`
- **THEN** the launcher warns about a malformed line without printing its contents

#### Scenario: Launcher-only names are not "dropped"
- **WHEN** the env file sets `RAPUNZEL_API_BASE_URL` for a harness that does not take it
- **THEN** the launcher reads it for egress and URL handling and does not list it as dropped

### Requirement: Host environment wins over the env file

When a name is set both in the host environment and in the env file, the launcher's own decisions (egress hosts, gateway keys, base URL) SHALL use the host value, matching Docker's precedence.

#### Scenario: Key in both places
- **WHEN** `OPENAI_API_KEY` is set on the host and in the env file
- **THEN** the gateway and the allowlist reasoning use the host value

### Requirement: Named key and base-URL variables

`RAPUNZEL_API_KEY_VARIABLE` and `RAPUNZEL_BASE_URL_VARIABLE`, from the host or the env file, SHALL be valid shell names that are not on the denylist, or the launcher exits with status 2. The key variable is added to the allowlist outside strict mode. The base-URL variable SHALL be set to the effective custom base URL (`RAPUNZEL_API_BASE_URL`, or the gateway route in strict mode) and requires a custom base URL.

#### Scenario: Key variable naming a denied name
- **WHEN** `RAPUNZEL_API_KEY_VARIABLE=NODE_OPTIONS`
- **THEN** the launcher exits with status 2

#### Scenario: Extension provider endpoint
- **WHEN** `RAPUNZEL_BASE_URL_VARIABLE=OMNIROUTE_BASE_URL` and `RAPUNZEL_API_BASE_URL=https://router.lan/v1` in open mode
- **THEN** the container receives `OMNIROUTE_BASE_URL=https://router.lan/v1`

### Requirement: Egress modes manage proxy and offline names

In `allowlist` mode, `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, and the profile's offline names SHALL NOT be forwarded from the host; the launcher sets its own. In `strict` mode only the profile's `H_ENV_ALLOW_GATEWAY` names SHALL be forwarded and credentials and the upstream URL go to the gateway instead. Any other allowlisted name set on the host that the gateway does not consume SHALL be reported as not passed; such names from the env file are reported as dropped.

#### Scenario: Host proxy in allowlist mode
- **WHEN** the host sets `HTTP_PROXY=http://corp:3128` and runs in allowlist mode
- **THEN** the container has no `HTTP_PROXY`, and `HTTPS_PROXY` points at the sidecar

#### Scenario: Extra key in strict mode
- **WHEN** `GEMINI_API_KEY` is set on the host in strict mode
- **THEN** the launcher warns that it is not passed and the container does not receive it

### Requirement: Secrets only at runtime

Credentials MUST enter only at runtime, through the filtered env file or explicitly forwarded variables, and never be baked into an image.

#### Scenario: Published image
- **WHEN** the image is inspected
- **THEN** it contains no provider key or token
