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

link_count() {
  path=$1
  if count=$(stat -f '%l' "$path" 2>/dev/null); then
    printf '%s\n' "$count"
  else
    stat -c '%h' "$path"
  fi
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
[ "$(link_count "$fresh/config/startup-memory-budget")" = 1 ] || fail 'default startup memory budget has multiple hard links'
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

for invalid_case in zero multiple-lines missing-newline hard-linked; do
  invalid="$TMP/invalid-$invalid_case"
  mkdir -p "$invalid/config"
  case "$invalid_case" in
    zero) printf '0\n' > "$invalid/config/startup-memory-budget" ;;
    multiple-lines) printf '9000\n9100\n' > "$invalid/config/startup-memory-budget" ;;
    missing-newline) printf '9000' > "$invalid/config/startup-memory-budget" ;;
    hard-linked)
      printf '9000\n' > "$invalid/budget-source"
      ln "$invalid/budget-source" "$invalid/config/startup-memory-budget"
      ;;
  esac
  if "$MATERIALIZER" "$invalid" >/dev/null 2>&1; then
    fail "$invalid_case startup memory budget did not fail closed"
  fi
  [ ! -e "$invalid/config/backend" ] || fail "$invalid_case budget failure partially materialized configuration"
done

race="$TMP/race"
race_bin="$TMP/race-bin"
mkdir -p "$race/config" "$race_bin"
real_ln=$(command -v ln)
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$2" = "$RACE_TARGET" ] && [ ! -e "$2" ]; then' \
  '  printf "captain-won\\n" > "$2"' \
  'fi' \
  'exec "$REAL_LN" "$@"' > "$race_bin/ln"
chmod +x "$race_bin/ln"
export REAL_LN="$real_ln"
export RACE_TARGET="$race/config/backend"
if PATH="$race_bin:$PATH" "$MATERIALIZER" "$race" >/dev/null 2>&1; then
  fail 'concurrent target publication did not fail closed'
fi
assert_eq 'captain-won' "$(cat "$race/config/backend")"

printf 'ok - config materialization, validation, preservation, and atomic publication contracts\n'
