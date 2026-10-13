#!/usr/bin/env bash
# Behavioral contract for the declared, locked Nix AXI toolchain.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$SCRIPT_DIR

if [ -n "${AXI_TOOLS_STORE_PATH:-}" ]; then
  AXI=$AXI_TOOLS_STORE_PATH
else
  AXI=$(cd "$ROOT" && nix build --impure --no-link --print-out-paths --no-write-lock-file \
    --expr 'let f = builtins.getFlake ("path:" + toString ./.); in (import ./nix/firstmate-toolchain.nix { pkgs = f.darwinPackages; }).axiTools')
fi

fail() {
  printf 'axi-toolchain.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  text=$1
  needle=$2
  label=$3
  printf '%s\n' "$text" | grep -Fq -- "$needle" || fail "$label does not mention '$needle'"
}

[ -x "$AXI/bin/tasks-axi" ] || fail "missing tasks-axi wrapper in $AXI"
[ -x "$AXI/bin/quota-axi" ] || fail "missing quota-axi wrapper in $AXI"

[ "$("$AXI/bin/tasks-axi" --version)" = '0.2.6' ] || fail 'unexpected tasks-axi version'
[ "$("$AXI/bin/quota-axi" --version)" = '0.1.51' ] || fail 'unexpected quota-axi version'

tasks_help=$("$AXI/bin/tasks-axi" --help)
quota_help=$("$AXI/bin/quota-axi" --help)
assert_contains "$tasks_help" 'add, list, show' 'tasks-axi help'
assert_contains "$tasks_help" '--backend <name>' 'tasks-axi help'
assert_contains "$quota_help" 'quota|auth|models' 'quota-axi help'
assert_contains "$quota_help" '--profile-only' 'quota-axi help'

TMP=$(mktemp -d "$ROOT/.axi-toolchain-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/home/.config" "$TMP/project/data" "$TMP/codex-profile" "$TMP/tmp"
printf '[markdown]\npath = "data/backlog.md"\narchive = "data/done-archive.md"\ndone_keep = 10\n' > "$TMP/project/.tasks.toml"
printf '# Fixture backlog\n\n' > "$TMP/project/data/backlog.md"

(
  cd "$TMP/project"
  env -i PATH="$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" TMPDIR="$TMP/tmp" \
    "$AXI/bin/tasks-axi" add fixture-task-q1 'Toolchain fixture' --kind ship --repo dotfiles --start --json \
    > "$TMP/tasks-add.json"
  grep -Fq '"ok": true' "$TMP/tasks-add.json" || fail 'tasks-axi did not confirm fixture mutation'
  grep -Fq '"id": "fixture-task-q1"' "$TMP/tasks-add.json" || fail 'tasks-axi response omitted fixture task id'
  grep -Fq 'fixture-task-q1' "$TMP/project/data/backlog.md" || fail 'tasks-axi did not update configured fixture backlog'
  env -i PATH="$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" TMPDIR="$TMP/tmp" \
    "$AXI/bin/tasks-axi" list --state in_flight > "$TMP/tasks-list.txt"
  grep -Fq 'fixture-task-q1' "$TMP/tasks-list.txt" || fail 'tasks-axi list did not read configured fixture task'
)

# Use an empty fixture profile in quota's explicitly read-only mode. Stream the
# report directly into a structural assertion; never retain or print its data.
set +o pipefail
env -i PATH=/usr/bin:/bin HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" \
  CODEX_HOME="$TMP/codex-profile" TMPDIR="$TMP/tmp" \
  "$AXI/bin/quota-axi" --provider codex --profile-only --json --no-credential-refresh \
  | jq -e 'has("generatedAt") and (.schemaVersion >= 5) and (.providers | length == 1 and .[0].provider == "codex" and (.[0].windows | type == "array"))' >/dev/null
quota_status=("${PIPESTATUS[@]}")
set -o pipefail
[ "${quota_status[0]}" -eq 1 ] || fail "empty fixture quota profile returned unexpected status ${quota_status[0]}"
[ "${quota_status[1]}" -eq 0 ] || fail 'quota-axi JSON did not satisfy the public schema contract'

printf 'axi-toolchain behavioral checks passed: tasks-axi 0.2.6, quota-axi 0.1.51\n'
