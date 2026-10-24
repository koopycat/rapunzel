#!/usr/bin/env bash
set -Eeuo pipefail

# Checks the clone workspace through the real launcher: the agent container
# has no host bind mount, host history arrives as origin/* without touching
# the agent's branches, agent commits arrive on the host only under
# refs/remotes/rapunzel-pi/*, and hooks, config, and tags planted in the
# workspace never reach the host repository. Needs git on the host; no
# network or credentials.

SCRIPT_PATH=${BASH_SOURCE[0]}
# Follow symlinks so a link on PATH still finds lib/ in the checkout.
while [[ -L "$SCRIPT_PATH" ]]; do
    link=$(readlink -- "$SCRIPT_PATH")
    [[ "$link" == /* ]] || link="$(dirname -- "$SCRIPT_PATH")/$link"
    SCRIPT_PATH=$link
done
ROOT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
# shellcheck source=lib/docker.sh
source "${ROOT_DIR}/lib/docker.sh"
# shellcheck source=lib/volumes.sh
source "${ROOT_DIR}/lib/volumes.sh"
IMAGE=${RAPUNZEL_IMAGE:-rapunzel}
VOLUME=${RAPUNZEL_VOLUME:-rapunzel-workspace-check}

require_docker verify-workspace.sh
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
    printf 'Image %s is missing. Run docker build -t %s . first.\n' "$IMAGE" "$IMAGE" >&2
    exit 1
}
command -v git >/dev/null 2>&1 || {
    printf 'git is required on the host for this check\n' >&2
    exit 1
}

# Clone mode mounts no host path, so the project may live anywhere.
project=$(mktemp -d "${TMPDIR:-/tmp}/rapunzel-workspace-check.XXXXXX")
project=$(cd -- "$project" && pwd -P)
report=$(mktemp "${TMPDIR:-/tmp}/rapunzel-workspace-report.XXXXXX")
workspace_volume=$(workspace_volume_name "$project" pi)
cleanup() {
    docker volume rm --force "$workspace_volume" >/dev/null 2>&1 || true
    rm -rf "$project" "$report"
}
trap cleanup EXIT

git -C "$project" init --quiet --initial-branch=main
git -C "$project" config user.name host
git -C "$project" config user.email host@example.invalid
printf 'base\n' >"${project}/README"
git -C "$project" add README
git -C "$project" commit --quiet -m base
host_main=$(git -C "$project" rev-parse main)
config_before=$(cat "${project}/.git/config")

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}
pass() { printf 'PASS %s\n' "$1"; }
# check WHAT COMMAND...: COMMAND must succeed; refute: it must fail.
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
refute() { local what=$1; shift; if "$@"; then fail "$what"; else pass "$what"; fi; }
has_line() { grep -q -- "$2" "$1"; }

launch() {
    # An empty RAPUNZEL_ENV_FILE also keeps the launcher's default env file out.
    env -u RAPUNZEL_EGRESS -u RAPUNZEL_HARNESS -u RAPUNZEL_WORKSPACE \
        RAPUNZEL_ENV_FILE= \
        RAPUNZEL_IMAGE="$IMAGE" \
        RAPUNZEL_VOLUME="$VOLUME" \
        "${ROOT_DIR}/rapunzel" "$@"
}

if launch --fetch "$project" 2>"$report"; then
    fail "--fetch succeeded before a workspace existed"
else
    pass "--fetch refuses a project without a workspace"
fi

# First run: the agent commits, plants a hook, git config, and a tag, writes
# a commit subject with a terminal escape, and leaves a file uncommitted. The
# host inspects the running container's mounts meanwhile.
# shellcheck disable=SC2016
first='
set -e
git rev-parse --abbrev-ref HEAD
printf "agent\n" >agent.txt
git add agent.txt
git commit --quiet -m "agent $(printf "\033[2J")commit"
printf "#!/bin/sh\necho hooked\n" >.git/hooks/post-merge
chmod +x .git/hooks/post-merge
git config core.fsmonitor ./evil
git tag agent-tag
printf "dirty\n" >uncommitted.txt
sleep 8
'
launch --clone --exec "$project" bash -c "$first" >"${report}.out" 2>"$report" &
launcher=$!
agent=""
for _ in $(seq 1 60); do
    agent=$(docker ps --filter "label=rapunzel.project=${project}" --filter label=rapunzel.role=agent --format '{{.ID}}' | head -n1)
    [[ -z "$agent" ]] || break
    sleep 0.5
done
if [[ -z "$agent" ]]; then
    fail "the clone-mode agent container did not start"
else
    mounts=$(docker inspect --format '{{range .Mounts}}{{.Type}} {{.Destination}}{{"\n"}}{{end}}' "$agent")
    if grep -q '^bind ' <<<"$mounts"; then
        fail "the clone-mode agent has a bind mount: $(grep '^bind ' <<<"$mounts" | tr '\n' ' ')"
    else
        pass "no host bind mount in clone mode"
    fi
    check "/workspace is the workspace volume" grep -qx 'volume /workspace' <<<"$mounts"
fi
wait "$launcher" || fail "the first clone run failed"

check "the workspace checks out the host branch" test "$(head -n1 "${report}.out")" == main
agent_main=$(git -C "$project" rev-parse --verify --quiet refs/remotes/rapunzel-pi/main || true)
agent_subject=""
[[ -z "$agent_main" ]] || agent_subject=$(git -C "$project" log -1 --format=%s "$agent_main")
check "the agent commit is at refs/remotes/rapunzel-pi/main" test "${agent_subject%%$'\033'*}" == 'agent '
check "the host main branch is unchanged" test "$(git -C "$project" rev-parse main)" == "$host_main"
refute "the planted hook stayed in the workspace" test -e "${project}/.git/hooks/post-merge"
check "the host git config is unchanged" test "$(cat "${project}/.git/config")" == "$config_before"
refute "agent tags are not fetched" git -C "$project" rev-parse --verify --quiet refs/tags/agent-tag
refute "the host checkout is untouched" test -e "${project}/agent.txt" -o -e "${project}/uncommitted.txt"
check "the new commit is reported" has_line "$report" 'rapunzel-pi/main: 1 new commit'
refute "workspace text is stripped of control characters" has_line "$report" $'\033'
check "uncommitted work is reported" has_line "$report" 'uncommitted changes'

# Second run: a host commit appears as origin/main and leaves the agent's
# branch alone; a commit that adds .envrc is flagged for review.
printf 'host\n' >>"${project}/README"
git -C "$project" commit --quiet -am "host commit"
host_main=$(git -C "$project" rev-parse main)
# shellcheck disable=SC2016
second='
set -e
printf "%s %s\n" "$(git rev-parse origin/main)" "$(git log -1 --format=%s main)"
printf "export X=1\n" >.envrc
git add .envrc uncommitted.txt
git commit --quiet -m "adds envrc"
'
launch --clone --exec "$project" bash -c "$second" >"${report}.out" 2>"$report" || fail "the second clone run failed"
read -r origin_main agent_subject <"${report}.out"
check "the host commit arrives as origin/main" test "$origin_main" == "$host_main"
check "the agent branch was not moved by the host update" test "${agent_subject%%$'\033'*}" == 'agent '
check "a commit adding .envrc is flagged" has_line "$report" 'review: touches .envrc'

# --fetch without starting the harness, with nothing new.
check "--fetch works without starting the harness" launch --fetch "$project" 2>"$report"
check "--fetch reports that nothing is new" has_line "$report" 'no new commits'

if [[ "$failures" -gt 0 ]]; then
    printf -- '--- rapunzel stderr ---\n' >&2
    cat "$report" >&2
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'PASS: clone workspace has no host mount, history moves only as checked bundles, nothing planted reaches the host\n'
