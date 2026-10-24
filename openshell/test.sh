#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

for file in \
    "$SCRIPT_DIR/Dockerfile" \
    "$SCRIPT_DIR/policy.yaml" \
    "$SCRIPT_DIR/provider-anthropic.yaml"; do
    [[ -s "$file" ]] || {
        printf 'missing or empty blueprint file: %s\n' "$file" >&2
        exit 1
    }
done

grep -q 'compatibility: hard_requirement' "$SCRIPT_DIR/policy.yaml"
grep -q '^network_policies: {}' "$SCRIPT_DIR/policy.yaml"
grep -q -- '--approval-mode manual' "$SCRIPT_DIR/pi-openshell"
grep -q -- '--no-auto-providers' "$SCRIPT_DIR/pi-openshell"
grep -q -- '--upload .:/workspace' "$SCRIPT_DIR/pi-openshell"
grep -q -- '--no-git-ignore' "$SCRIPT_DIR/pi-openshell"
if grep -Eq -- '--mount|type=bind|docker\.sock' "$SCRIPT_DIR/pi-openshell"; then
    printf 'pi-openshell contains a forbidden host-mount primitive\n' >&2
    exit 1
fi

# Exercise snapshot creation and argument checks without a running gateway.
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT
cat >"$stub_dir/openshell" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${OPENSHELL_STUB_LOG:?}"
EOF
chmod 0755 "$stub_dir/openshell"

project="$stub_dir/project"
mkdir "$project"
git -C "$project" init -q
git -C "$project" config user.name test
git -C "$project" config user.email test@invalid
printf 'visible\n' >"$project/tracked.txt"
printf 'ignored\n' >"$project/secret.env"
printf 'secret.env\n' >"$project/.gitignore"
git -C "$project" add .gitignore tracked.txt
git -C "$project" commit -qm baseline

log="$stub_dir/create.log"
PATH="$stub_dir:$PATH" OPENSHELL_STUB_LOG="$log" OPENSHELL_PI_NAME=test-sandbox \
    "$SCRIPT_DIR/pi-openshell" create "$project"
grep -qx -- '--upload' "$log"
grep -qx -- '.:/workspace' "$log"

# A tracked deletion represents the current worktree state and must not break
# snapshot creation.
rm "$project/tracked.txt"
PATH="$stub_dir:$PATH" OPENSHELL_STUB_LOG="$log" OPENSHELL_PI_NAME=test-sandbox \
    "$SCRIPT_DIR/pi-openshell" create "$project"

printf 'secret\n' >"$project/.env.local"
if PATH="$stub_dir:$PATH" OPENSHELL_STUB_LOG="$log" OPENSHELL_PI_NAME=test-sandbox \
    "$SCRIPT_DIR/pi-openshell" create "$project" 2>/dev/null; then
    printf 'suspicious upload path unexpectedly accepted\n' >&2
    exit 1
fi

if PATH="$stub_dir:$PATH" OPENSHELL_STUB_LOG="$log" \
    "$SCRIPT_DIR/pi-openshell" export invalid/name "$stub_dir/export" 2>/dev/null; then
    printf 'invalid sandbox name unexpectedly accepted\n' >&2
    exit 1
fi

printf 'PASS: OpenShell blueprint checks\n'
