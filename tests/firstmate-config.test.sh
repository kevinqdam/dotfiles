#!/usr/bin/env bash
# Behavioral contract for safe canonical-home configuration materialization.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MATERIALIZER="$SCRIPT_DIR/agents/materialize-firstmate-config"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-config-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'firstmate-config.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

fresh="$TMP/fresh"
"$MATERIALIZER" "$fresh" >/dev/null
for name in backend crew-harness crew-dispatch.json startup-memory-budget; do
  [ -f "$fresh/config/$name" ] || fail "missing $name"
  [ ! -L "$fresh/config/$name" ] || fail "$name is a symlink"
done
assert_eq 'herdr' "$(cat "$fresh/config/backend")"
assert_eq 'pi' "$(cat "$fresh/config/crew-harness")"
assert_eq '7500' "$(cat "$fresh/config/startup-memory-budget")"
jq -e '
  (.rules | length) == 2
  and .rules[0].use == {harness: "pi", model: "gpt-5.6-luna", effort: "max"}
  and .rules[1].use == {harness: "pi", model: "gpt-5.6-sol", effort: "high"}
  and .default == {harness: "pi", model: "gpt-5.6-sol", effort: "medium"}
' "$fresh/config/crew-dispatch.json" >/dev/null || fail 'dispatch defaults are not the approved semantic configuration'

populated="$TMP/populated"
mkdir -p "$populated/config" "$populated/data" "$populated/state" "$populated/projects"
printf 'agy\n' > "$populated/config/crew-harness"
printf '9100\n' > "$populated/config/startup-memory-budget"
printf 'captain runtime\n' > "$populated/data/captain.md"
printf 'runtime state\n' > "$populated/state/sentinel"
"$MATERIALIZER" "$populated" >/dev/null
assert_eq 'agy' "$(cat "$populated/config/crew-harness")"
assert_eq '9100' "$(cat "$populated/config/startup-memory-budget")"
assert_eq 'captain runtime' "$(cat "$populated/data/captain.md")"
assert_eq 'runtime state' "$(cat "$populated/state/sentinel")"
assert_eq 'herdr' "$(cat "$populated/config/backend")"

conflict="$TMP/conflict"
mkdir -p "$conflict/config"
printf 'captain-owned\n' > "$conflict/backend-target"
ln -s ../backend-target "$conflict/config/backend"
if "$MATERIALIZER" "$conflict" >/dev/null 2>&1; then
  fail 'symlink conflict did not fail closed'
fi
[ -L "$conflict/config/backend" ] || fail 'symlink conflict was replaced'
assert_eq '../backend-target' "$(readlink "$conflict/config/backend")"

printf 'ok - config materialization, semantic dispatch defaults, preservation, and conflict contracts\n'
