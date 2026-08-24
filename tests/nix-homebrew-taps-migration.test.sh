#!/usr/bin/env bash
# Behavioral contract for the native nix-homebrew Taps migration boundary.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MIGRATOR="$SCRIPT_DIR/agents/migrate-empty-homebrew-taps"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nix-homebrew-taps-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'nix-homebrew-taps-migration.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

expect_refusal() {
  local name=$1
  local library=$2
  local expected_owner=$3
  if "$MIGRATOR" "$library" "$expected_owner" "$managed_symlink_owner" \
    "$managed_symlink_group" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
    fail "$name path was accepted"
  fi
}

owner=$(id -un)
managed_symlink_owner=$owner
managed_symlink_group=$(id -gn)
arm_library="$TMP/opt/homebrew/Library"
intel_library="$TMP/usr/local/Homebrew/Library"
mkdir -p "$arm_library/Taps" "$intel_library/Taps"

# This is the reported post-migration shape: ARM has an empty ordinary legacy
# directory while Intel has real unrelated taps that must not be touched.
for tap in \
  heroku/homebrew-brew \
  homebrew/homebrew-core \
  homebrew/homebrew-cask \
  planetscale/homebrew-tap \
  dart-lang/homebrew-dart \
  sass/homebrew-sass; do
  mkdir -p "$intel_library/Taps/$tap"
  printf '%s\n' "$tap" > "$intel_library/Taps/$tap/sentinel"
done
intel_before=$(find "$intel_library/Taps" -print | LC_ALL=C sort)
managed_taps="$TMP/managed-taps"
mkdir -p "$managed_taps"

# Reproduce nix-homebrew's locked declarative-taps masking check in an
# isolated fixture before preparing it. Both existing ordinary paths fail.
declarative_link() {
  path=$1
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    return 1
  fi
  ln -s "$managed_taps" "$path"
}
if declarative_link "$arm_library/Taps"; then
  fail 'empty ARM Taps fixture did not reproduce the upstream masking failure'
fi
if declarative_link "$intel_library/Taps"; then
  fail 'populated Intel Taps fixture did not reproduce the upstream masking failure'
fi

"$MIGRATOR" "$arm_library" "$owner" "$managed_symlink_owner" \
  "$managed_symlink_group" >"$TMP/arm-first.out" 2>"$TMP/arm-first.err"
[ ! -e "$arm_library/Taps" ] || fail 'empty ARM Taps directory was not removed'
[ ! -L "$arm_library/Taps" ] || fail 'empty ARM Taps symlink was created by migration'
grep -Fq "$arm_library/Taps" "$TMP/arm-first.err" || fail 'ARM removal was not reported'

# The second activation sees a missing path and must be a no-op.
"$MIGRATOR" "$arm_library" "$owner" "$managed_symlink_owner" \
  "$managed_symlink_group" >"$TMP/arm-second.out" 2>"$TMP/arm-second.err"
[ ! -s "$TMP/arm-second.err" ] || fail 'idempotent ARM migration emitted an error'
intel_after=$(find "$intel_library/Taps" -print | LC_ALL=C sort)
assert_eq "$intel_before" "$intel_after"
[ -f "$intel_library/Taps/heroku/homebrew-brew/sentinel" ] || fail 'Intel taps were changed'

# Refuse every ambiguous or unsafe shape without changing it.
nonempty="$TMP/nonempty/Library"
mkdir -p "$nonempty/Taps/tap"
expect_refusal nonempty "$nonempty" "$owner"
[ -d "$nonempty/Taps/tap" ] || fail 'non-empty Taps directory was changed'

symlink_target="$TMP/symlink-target"
symlink_case="$TMP/symlink/Library"
mkdir -p "$symlink_target" "$symlink_case"
ln -s "$symlink_target" "$symlink_case/Taps"
expect_refusal symlink "$symlink_case" "$owner"
[ -L "$symlink_case/Taps" ] || fail 'Taps symlink was replaced'
[ -d "$symlink_target" ] || fail 'symlink target was changed'

dangling_case="$TMP/dangling/Library"
mkdir -p "$dangling_case"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-taps-env "$dangling_case/Taps"
expect_refusal dangling "$dangling_case" "$owner"
[ -L "$dangling_case/Taps" ] || fail 'dangling Taps symlink was replaced'

file_case="$TMP/file/Library"
mkdir -p "$file_case"
printf 'captain state\n' > "$file_case/Taps"
expect_refusal file "$file_case" "$owner"
[ -f "$file_case/Taps" ] || fail 'Taps file was replaced'
assert_eq 'captain state' "$(cat "$file_case/Taps")"

unreadable="$TMP/unreadable/Library"
mkdir -p "$unreadable/Taps"
chmod u-rx "$unreadable/Taps"
expect_refusal unreadable "$unreadable" "$owner"
chmod u+rwx "$unreadable/Taps"
[ -d "$unreadable/Taps" ] || fail 'unreadable Taps directory was changed'

wrong_owner="$TMP/wrong-owner/Library"
mkdir -p "$wrong_owner/Taps"
if [ "$(id -u)" -eq 0 ]; then
  wrong_owner_name=nobody
else
  wrong_owner_name=root
fi
if id -u "$wrong_owner_name" >/dev/null 2>&1 && [ "$(id -u "$wrong_owner_name")" != "$(id -u)" ]; then
  expect_refusal wrong-owner "$wrong_owner" "$wrong_owner_name"
else
  expect_refusal unresolved-owner "$wrong_owner" __missing_nix_homebrew_owner__
fi
[ -d "$wrong_owner/Taps" ] || fail 'wrong-owner Taps directory was changed'

# Verify the evaluated system owns only ARM Homebrew. This is the declarative
# boundary that prevents the real /usr/local tree from entering activation.
command -v nix >/dev/null 2>&1 || fail 'nix is required for prefix-boundary validation'
command -v jq >/dev/null 2>&1 || fail 'jq is required for prefix-boundary validation'
system=$(cd "$SCRIPT_DIR" && nix build .#darwinConfigurations.macbook.system \
  --no-link --print-out-paths)
setup_text=$(cd "$SCRIPT_DIR" && nix eval --impure --raw --no-write-lock-file \
  '.#darwinConfigurations.macbook.config.system.activationScripts.setup-homebrew.text')
setup_script=$(printf '%s\n' "$setup_text" | awk '/-setup-homebrew$/ { print $1 }')
[ -x "$setup_script" ] || fail 'built setup-homebrew script is unavailable'
if grep -Fq 'HOMEBREW_PREFIX="/usr/local"' "$setup_script" \
  || grep -Fq 'setting up Homebrew (/usr/local)' "$setup_script"; then
  fail 'built activation still attempts to set up the disabled Intel prefix'
fi
[ -x "$system/activate" ] || fail 'locked system activation output is unavailable'
printf '%s\n' "$setup_text" | awk '$1 == "root" { found = 1 } END { exit !found }' \
  || fail 'activation does not pass root as the managed symlink owner'
printf '%s\n' "$setup_text" | awk '$1 == "admin" { found = 1 } END { exit !found }' \
  || fail 'activation does not pass admin as the managed symlink group'

managed_target=$(find /nix/store -maxdepth 1 -type d -name '*-taps-env' \
  | LC_ALL=C sort | head -1)
[ -n "$managed_target" ] || fail 'built nix-homebrew taps environment is unavailable'

# A symlink with a valid managed target but the wrong lstat owner is also
# ambiguous and must remain untouched.
wrong_symlink="$TMP/wrong-symlink/Library"
mkdir -p "$wrong_symlink"
ln -s "$managed_target" "$wrong_symlink/Taps"
if [ "$(id -u)" -eq 0 ]; then
  wrong_symlink_owner=nobody
else
  wrong_symlink_owner=root
fi
if id -u "$wrong_symlink_owner" >/dev/null 2>&1 \
  && [ "$(id -u "$wrong_symlink_owner")" != "$(id -u)" ]; then
  if "$MIGRATOR" "$wrong_symlink" "$owner" "$wrong_symlink_owner" \
    "$managed_symlink_group" >"$TMP/wrong-symlink.out" 2>"$TMP/wrong-symlink.err"; then
    fail 'wrong-owner managed-shaped symlink was accepted'
  fi
  [ -L "$wrong_symlink/Taps" ] || fail 'wrong-owner symlink was replaced'
fi

# The first activation removes an empty ordinary path; nix-homebrew then
# creates this exact root-owned managed symlink. Repeated activation must
# accept and preserve it rather than treating it as legacy state.
repeat_library="$TMP/repeat/Library"
mkdir -p "$repeat_library/Taps"
"$MIGRATOR" "$repeat_library" "$owner" root admin
[ ! -e "$repeat_library/Taps" ] || fail 'repeat fixture did not remove its empty legacy directory'
ln -s "$managed_target" "$repeat_library/Taps"
"$MIGRATOR" "$repeat_library" "$owner" "$managed_symlink_owner" \
  "$managed_symlink_group"
[ "$(readlink "$repeat_library/Taps")" = "$managed_target" ] \
  || fail 'managed Taps symlink was not preserved'

prefixes=$(cd "$SCRIPT_DIR" && nix eval --impure --json --no-write-lock-file \
  '.#darwinConfigurations.macbook.config.nix-homebrew.prefixes')
printf '%s\n' "$prefixes" | jq -e '
  .["/opt/homebrew"].enable == true
  and .["/opt/homebrew"].library == "/opt/homebrew/Library"
  and .["/usr/local"].enable == false
  and .["/usr/local"].library == "/usr/local/Homebrew/Library"
' >/dev/null || fail 'evaluated nix-homebrew prefix boundary is incorrect'

# Drive the fixture from the evaluated enabled-prefix set and inspect the
# observable activation messages. The disabled Intel prefix must not appear.
enabled_prefixes=$(printf '%s\n' "$prefixes" | jq -r '
  to_entries[] | select(.value.enable) | .key
')
assert_eq /opt/homebrew "$enabled_prefixes"
printf '%s\n' "$enabled_prefixes" | while IFS= read -r prefix; do
  case "$prefix" in
    /opt/homebrew)
      "$MIGRATOR" "$arm_library" "$owner" "$managed_symlink_owner" \
        "$managed_symlink_group"
      ln -s "$managed_taps" "$arm_library/Taps"
      printf 'setting up Homebrew (%s)\n' "$prefix" >> "$TMP/activation.log"
      ;;
    /usr/local)
      fail 'activation attempted to set up the disabled Intel prefix'
      ;;
    *)
      fail "activation encountered an unexpected Homebrew prefix: $prefix"
      ;;
  esac
done
if grep -Fq '/usr/local' "$TMP/activation.log"; then
  fail 'activation attempted to set up the disabled Intel prefix'
fi
[ -L "$arm_library/Taps" ] || fail 'ARM declarative Taps link was not possible'

printf 'ok - native empty-Taps migration, Intel preservation, refusal, idempotence, and prefix boundary contracts\n'
