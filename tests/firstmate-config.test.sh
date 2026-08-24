#!/usr/bin/env bash
# Behavioral contract for safe canonical-home configuration materialization.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MATERIALIZER_SOURCE="$SCRIPT_DIR/agents/materialize-firstmate-config.c"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-config-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
MATERIALIZER="$TMP/materialize-firstmate-config"
stopped_pid=

cleanup() {
  if [ -n "$stopped_pid" ]; then
    kill -CONT "$stopped_pid" >/dev/null 2>&1 || true
    kill "$stopped_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'firstmate-config.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

wait_until_stopped() {
  pid=$1
  attempt=0
  while [ "$attempt" -lt 200 ]; do
    state=$(ps -o state= -p "$pid" 2>/dev/null || true)
    case "$state" in
      *T*) return 0 ;;
    esac
    kill -0 "$pid" 2>/dev/null || fail 'materializer exited before test hook'
    sleep 0.01
    attempt=$((attempt + 1))
  done
  fail 'materializer did not reach test hook'
}

start_hooked() {
  hook=$1
  target_home=$2
  FIRSTMATE_CONFIG_TEST_HOOK="$hook" "$MATERIALIZER" "$target_home" >/dev/null 2>&1 &
  stopped_pid=$!
  wait_until_stopped "$stopped_pid"
}

finish_hooked_failure() {
  message=$1
  kill -CONT "$stopped_pid"
  if wait "$stopped_pid"; then
    stopped_pid=
    fail "$message"
  fi
  stopped_pid=
}

${CC:-cc} -std=c11 -Wall -Wextra -Werror -DFIRSTMATE_CONFIG_TESTING \
  "$MATERIALIZER_SOURCE" -o "$MATERIALIZER"

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

for invalid_case in zero leading-zero multiple-lines missing-newline hard-linked; do
  invalid="$TMP/invalid-$invalid_case"
  mkdir -p "$invalid/config"
  case "$invalid_case" in
    zero) printf '0\n' > "$invalid/config/startup-memory-budget" ;;
    leading-zero) printf '0001\n' > "$invalid/config/startup-memory-budget" ;;
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
mkdir -p "$race/config"
start_hooked before-publish "$race"
printf 'captain-won\n' > "$race/config/startup-memory-budget"
finish_hooked_failure 'concurrent target publication did not fail closed'
assert_eq 'captain-won' "$(cat "$race/config/startup-memory-budget")"

replacement_race="$TMP/preservation-replacement"
mkdir -p "$replacement_race/config"
printf '9100\n' > "$replacement_race/config/startup-memory-budget"
printf 'abcd\n' > "$replacement_race/replacement-budget"
start_hooked before-preserve-boundary "$replacement_race"
mv "$replacement_race/replacement-budget" "$replacement_race/config/startup-memory-budget"
finish_hooked_failure 'atomic startup budget replacement did not fail closed'
assert_eq 'abcd' "$(cat "$replacement_race/config/startup-memory-budget")"

rewrite_race="$TMP/preservation-rewrite"
mkdir -p "$rewrite_race/config"
printf '9100\n' > "$rewrite_race/config/startup-memory-budget"
start_hooked before-preserve-boundary "$rewrite_race"
printf 'abcd\n' > "$rewrite_race/config/startup-memory-budget"
touch -t 200001010000 "$rewrite_race/config/startup-memory-budget"
finish_hooked_failure 'in-place startup budget rewrite did not fail closed'
assert_eq 'abcd' "$(cat "$rewrite_race/config/startup-memory-budget")"

directory_race="$TMP/directory-replacement"
outside_config="$TMP/outside-config"
mkdir -p "$directory_race/config" "$outside_config"
start_hooked after-config-open "$directory_race"
mv "$directory_race/config" "$directory_race/original-config"
ln -s "$outside_config" "$directory_race/config"
finish_hooked_failure 'canonical config directory replacement did not fail closed'
for name in backend crew-harness crew-dispatch.json startup-memory-budget; do
  [ ! -e "$outside_config/$name" ] || fail "directory replacement escaped through $name"
done

printf 'ok - config materialization, validation, preservation, and atomic publication contracts\n'
