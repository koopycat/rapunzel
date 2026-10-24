# Spec Delta

## ADDED Requirements

### Requirement: Resource limits for the agent process

The agent container SHALL start with a process limit, 4096 by default or `RAPUNZEL_PIDS_LIMIT` (an integer from 64 up), and with a memory limit only when `RAPUNZEL_MEMORY` is set (a Docker size such as `8g`, at least 64 MiB). An invalid value MUST stop the launcher with an error before any Docker resource is created.

#### Scenario: Default process limit
- **WHEN** the agent runs with no limit variables set
- **THEN** the container's cgroup process limit is 4096 and no memory limit is set

#### Scenario: Custom limits
- **WHEN** `RAPUNZEL_PIDS_LIMIT=8192` and `RAPUNZEL_MEMORY=8g` are set
- **THEN** the container's cgroup limits are 8192 processes and 8 GiB of memory

#### Scenario: Fork bomb
- **WHEN** a process in the agent container forks without bound
- **THEN** new forks fail once the process limit is reached, and the Docker engine and other containers keep running

#### Scenario: Invalid limit
- **WHEN** `RAPUNZEL_PIDS_LIMIT=unlimited` or `RAPUNZEL_MEMORY=lots` is set
- **THEN** the launcher prints which variable is invalid and exits before starting Docker
