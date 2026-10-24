#!/usr/bin/env bash
# Clone workspace: the agent works on a git clone in a named volume instead of
# the host checkout. History moves only as git bundles over stdin and stdout of
# a short-lived helper container, so the host never runs git in, or reads the
# configuration of, a repository the agent controlled.
#
# Volume layout: the root holds the ownership marker, repo/ holds the clone and
# is what the agent sees at /workspace (a volume subpath mount).
#
# Source this file from the launcher after lib/volumes.sh and lib/host-files.sh.
# It defines:
#   workspace_require_repo PROJECT - stop unless PROJECT is a git repo with a commit
#   workspace_seed                 - send the host's branches and tags into the workspace
#   workspace_fetch                - fetch the workspace's branches to the host and report
# and reads IMAGE, H_NAME, PROJECT_DIR, and WORKSPACE_VOLUME.

workspace_require_repo() {
    local project=${1:?workspace_require_repo requires a project directory}
    command -v git >/dev/null 2>&1 || {
        printf 'rapunzel: the clone workspace needs git on the host\n' >&2
        return 1
    }
    [[ "$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)" == "$project" ]] || {
        printf 'rapunzel: the clone workspace needs the top level of a git repository, not %s\n' "$project" >&2
        return 1
    }
    git -C "$project" rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null || {
        printf 'rapunzel: the clone workspace needs a repository with at least one commit\n' >&2
        return 1
    }
}

# Run a bash script in a helper container that has only the workspace volume,
# at /w. Extra arguments become the script's positional parameters. The
# repository config is the agent's, so the helper's git ignores the settings
# that would run commands on its own (fsmonitor, hooks); everything it does is
# confined to this networkless container and the volume anyway.
_workspace_helper() {
    local script=$1
    shift
    docker run --rm --interactive \
        --network none \
        --read-only --tmpfs /tmp \
        --user "$(id -u):$(id -g)" \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --env HOME=/tmp \
        --env GIT_COMMITTER_NAME=rapunzel --env GIT_COMMITTER_EMAIL=rapunzel@localhost \
        --env GIT_CONFIG_COUNT=2 \
        --env GIT_CONFIG_KEY_0=core.fsmonitor --env GIT_CONFIG_VALUE_0=false \
        --env GIT_CONFIG_KEY_1=core.hooksPath --env GIT_CONFIG_VALUE_1=/dev/null \
        --mount "type=volume,src=${WORKSPACE_VOLUME},dst=/w" \
        --entrypoint /bin/bash \
        "$IMAGE" -euo pipefail -c "$script" -- "$@"
}

# Write a bundle of REPO's refs to OUT, or an empty file when there is nothing
# new to send. A rev-list check alone would miss a new annotated tag on a commit
# the other side already has, so ask git and accept only its empty-bundle refusal.
_workspace_bundle() {
    local repo=$1 out=$2 error
    shift 2
    if error=$(LC_ALL=C git -C "$repo" bundle create --quiet "$out" "$@" 2>&1); then
        return 0
    fi
    if [[ "$error" == *"Refusing to create empty bundle"* ]]; then
        : >"$out"
        return 0
    fi
    printf 'rapunzel: git bundle failed: %s\n' "$error" >&2
    return 1
}

# Strip terminal control characters from text that came from the workspace.
_workspace_safe() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

workspace_volume_exists() { docker volume inspect "$WORKSPACE_VOLUME" >/dev/null 2>&1; }

# Host -> workspace. The first run clones; later runs update refs/remotes/origin/*
# and the host's tags, and never touch the agent's branches or working tree.
workspace_seed() {
    local dir known refs head_ref head_oid name email oid
    dir=$(mktemp -d "${TMPDIR:-/tmp}/rapunzel-workspace.XXXXXX")
    prepare_volume_owner "$WORKSPACE_VOLUME" /w

    # Object IDs the workspace already has from earlier runs, to send less.
    # shellcheck disable=SC2016
    known=$(_workspace_helper '
        [[ -d /w/repo/.git ]] || exit 0
        git -C /w/repo for-each-ref --format="%(objectname)" refs/remotes/origin refs/tags
    ' | grep -E '^[0-9a-f]{40,64}$' || true)

    git -C "$PROJECT_DIR" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags >"${dir}/refs"
    refs=$(wc -l <"${dir}/refs" | tr -d ' ')
    local excludes=()
    for oid in $known; do
        git -C "$PROJECT_DIR" cat-file -e "${oid}^{commit}" 2>/dev/null && excludes+=("^${oid}")
    done
    _workspace_bundle "$PROJECT_DIR" "${dir}/bundle" --branches --tags ${excludes[@]+"${excludes[@]}"}
    head_ref=$(git -C "$PROJECT_DIR" symbolic-ref --quiet HEAD || true)
    head_oid=$(git -C "$PROJECT_DIR" rev-parse HEAD)
    name=$(git -C "$PROJECT_DIR" config user.name || true)
    email=$(git -C "$PROJECT_DIR" config user.email || true)

    # Framing on stdin: the ref count, the ref lines, then the bundle bytes.
    # The script runs in the helper, so its expansions stay unexpanded here.
    # shellcheck disable=SC2016
    {
        printf '%s\n' "$refs"
        cat "${dir}/refs"
        cat "${dir}/bundle"
    } | _workspace_helper '
        read -r count
        refs=$(for ((i = 0; i < count; i++)); do read -r line; printf "%s\n" "$line"; done)
        cat >/tmp/host.bundle
        fresh=false
        if [[ ! -d /w/repo/.git ]]; then
            rm -rf /w/repo
            git init --quiet /w/repo
            fresh=true
        fi
        cd /w/repo
        [[ ! -s /tmp/host.bundle ]] || git fetch --quiet --no-tags --no-write-fetch-head /tmp/host.bundle "refs/*:refs/rapunzel-incoming/*"
        git for-each-ref --format="%(refname)" refs/rapunzel-incoming | while read -r ref; do git update-ref -d "$ref"; done
        # Mirror host branches as origin/* and host tags as tags; drop what the host deleted.
        wanted=$(mktemp)
        while read -r oid ref; do
            case "$ref" in
                refs/heads/*) target="refs/remotes/origin/${ref#refs/heads/}" ;;
                refs/tags/*) target=$ref ;;
                *) continue ;;
            esac
            git update-ref "$target" "$oid"
            printf "%s\n" "$target" >>"$wanted"
        done <<<"$refs"
        git for-each-ref --format="%(refname)" refs/remotes/origin | while read -r ref; do
            grep -qxF "$ref" "$wanted" || git update-ref -d "$ref"
        done
        if [[ "$fresh" == true ]]; then
            [[ -z "$3" ]] || git config user.name "$3"
            [[ -z "$4" ]] || git config user.email "$4"
            branch=${1#refs/heads/}
            if [[ -n "$1" ]] && git rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
                git checkout --quiet -B "$branch" "refs/remotes/origin/${branch}"
            else
                git checkout --quiet --detach "$2"
            fi
        fi
    ' "$head_ref" "$head_oid" "$name" "$email"
    rm -rf -- "$dir"

    if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal 2>/dev/null | head -n1)" ]]; then
        printf 'rapunzel: uncommitted changes and untracked files in %s are not in the clone workspace\n' "$PROJECT_DIR" >&2
    fi
}

# Workspace -> host. Agent branches land in refs/remotes/rapunzel-<harness>/*
# only; objects are checked on the way in, ref names and object IDs from the
# workspace are validated, and text from it is stripped of control characters
# before it reaches the terminal.
workspace_fetch() {
    local dir namespace dirty count i line oid name ref old changed=0 commit path pattern
    dir=$(mktemp -d "${TMPDIR:-/tmp}/rapunzel-workspace.XXXXXX")
    namespace="refs/remotes/rapunzel-${H_NAME}"

    # Commits the host already has, so the bundle carries only new history.
    git -C "$PROJECT_DIR" for-each-ref --format='%(objectname)' refs/heads "$namespace" | sort -u >"${dir}/have"

    # Framing on stdout: the dirty flag, the ref count, the ref lines, then the bundle.
    # shellcheck disable=SC2016
    if ! _workspace_helper '
        cd /w/repo
        have=$(cat)
        dirty=0
        [[ -z "$(git status --porcelain --untracked-files=normal | head -n1)" ]] || dirty=1
        excludes=()
        for oid in $have; do
            git cat-file -e "${oid}^{commit}" 2>/dev/null && excludes+=("^${oid}")
        done
        git for-each-ref --format="%(objectname) %(refname)" refs/heads >/tmp/refs
        printf "%s\n%s\n" "$dirty" "$(wc -l </tmp/refs | tr -d " ")"
        cat /tmp/refs
        if ! error=$(LC_ALL=C git bundle create --quiet /tmp/out.bundle --branches ${excludes[@]+"${excludes[@]}"} 2>&1); then
            [[ "$error" == *"Refusing to create empty bundle"* ]] || { printf "%s\n" "$error" >&2; exit 1; }
            : >/tmp/out.bundle
        fi
        cat /tmp/out.bundle
    ' <"${dir}/have" >"${dir}/stream" 2>"${dir}/errors"; then
        rm -rf -- "$dir"
        printf 'rapunzel: could not read the clone workspace\n' >&2
        return 1
    fi

    {
        read -r dirty
        read -r count
        if [[ ! "$dirty" =~ ^[01]$ || ! "$count" =~ ^[0-9]{1,6}$ ]]; then
            printf 'rapunzel: the clone workspace sent a malformed ref list; nothing fetched\n' >&2
            rm -rf -- "$dir"
            return 1
        fi
        : >"${dir}/refs"
        for ((i = 0; i < count; i++)); do
            read -r line
            if [[ ! "$line" =~ ^([0-9a-f]{40}|[0-9a-f]{64})\ refs/heads/(.+)$ ]] ||
                ! git check-ref-format "refs/heads/${BASH_REMATCH[2]}"; then
                printf 'rapunzel: the clone workspace sent an invalid ref; nothing fetched\n' >&2
                rm -rf -- "$dir"
                return 1
            fi
            printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >>"${dir}/refs"
        done
        cat >"${dir}/bundle"
    } <"${dir}/stream"

    if [[ -s "${dir}/bundle" ]] &&
        ! git -C "$PROJECT_DIR" -c transfer.fsckObjects=true -c fetch.fsckObjects=true \
            fetch --quiet --no-tags --no-write-fetch-head "${dir}/bundle" \
            "+refs/heads/*:refs/rapunzel-incoming/${H_NAME}/*"; then
        printf 'rapunzel: the clone workspace bundle was rejected; nothing fetched\n' >&2
        rm -rf -- "$dir"
        return 1
    fi
    git -C "$PROJECT_DIR" for-each-ref --format='%(refname)' "refs/rapunzel-incoming/${H_NAME}" |
        while read -r ref; do git -C "$PROJECT_DIR" update-ref -d "$ref"; done

    # Mirror the workspace's branches exactly, and keep the old tips for the report.
    git -C "$PROJECT_DIR" for-each-ref --format='%(objectname) %(refname)' "$namespace" >"${dir}/old"
    while read -r oid name; do
        if ! git -C "$PROJECT_DIR" cat-file -e "${oid}^{commit}" 2>/dev/null; then
            printf 'rapunzel: the clone workspace names a commit the host does not have; skipped %s\n' \
                "$(_workspace_safe <<<"$name")" >&2
            continue
        fi
        old=$(awk -v ref="${namespace}/${name}" '$2 == ref { print $1 }' "${dir}/old")
        [[ "$old" == "$oid" ]] && continue
        git -C "$PROJECT_DIR" update-ref "${namespace}/${name}" "$oid"
        printf '%s %s %s\n' "${old:-none}" "$oid" "$name" >>"${dir}/changed"
    done <"${dir}/refs"
    while read -r oid ref; do
        awk -v name="${ref#"${namespace}"/}" '$2 == name { found = 1 } END { exit !found }' "${dir}/refs" && continue
        git -C "$PROJECT_DIR" update-ref -d "$ref"
        printf 'rapunzel: %s deleted branch %s in the clone workspace; removed %s\n' "$H_NAME" \
            "$(_workspace_safe <<<"${ref#"${namespace}"/}")" "$(_workspace_safe <<<"$ref")" >&2
    done <"${dir}/old"

    # Review report: commits new to the host, and those touching host-executed paths.
    if [[ -s "${dir}/changed" ]]; then
        while read -r old oid name; do
            local not=(--not --branches)
            [[ "$old" == none ]] || not+=("$old")
            git -C "$PROJECT_DIR" rev-list --reverse "$oid" "${not[@]}" >"${dir}/commits"
            # A branch moved to commits the host already has needs no review.
            [[ -s "${dir}/commits" ]] || continue
            changed=1
            printf 'rapunzel: %s/%s: %s new commit(s) from the clone workspace\n' "rapunzel-${H_NAME}" \
                "$(_workspace_safe <<<"$name")" "$(wc -l <"${dir}/commits" | tr -d ' ')" >&2
            while read -r commit; do
                printf '  %s\n' "$(git -C "$PROJECT_DIR" log -1 --format='%h %s' "$commit" | _workspace_safe)" >&2
                git -C "$PROJECT_DIR" diff-tree -r -m --root --no-commit-id --name-only "$commit" |
                    sort -u >"${dir}/paths"
                while IFS= read -r path; do
                    for pattern in "${HOST_EXECUTED_PATHS[@]}"; do
                        if [[ "$path" == "$pattern" || "$path" == "$pattern"/* ]]; then
                            printf '    review: touches %s, which the host may run on its own\n' \
                                "$(_workspace_safe <<<"$path")" >&2
                            break
                        fi
                    done
                done <"${dir}/paths"
            done <"${dir}/commits"
        done <"${dir}/changed"
    fi
    if [[ "$changed" == 1 ]]; then
        printf "rapunzel: review with git log -p --remotes='rapunzel-%s/*' --not --branches, then merge what you want.\n" \
            "$H_NAME" >&2
    fi
    [[ "$changed" == 1 ]] || printf 'rapunzel: no new commits in the clone workspace\n' >&2
    if [[ "$dirty" == 1 ]]; then
        printf 'rapunzel: the clone workspace has uncommitted changes; they stay in the volume and were not fetched\n' >&2
    fi
    rm -rf -- "$dir"
}
