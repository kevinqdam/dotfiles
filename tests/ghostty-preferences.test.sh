#!/usr/bin/env bash
# Behavioral contract for Ghostty preference links and Home Manager backups.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'ghostty-preferences.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

file_inode() {
  if stat -c '%i' "$1" >/dev/null 2>&1; then
    stat -c '%i' "$1"
  else
    stat -f '%i' "$1"
  fi
}

source_file="$REPO_ROOT/ghostty/config.ghostty"
relative='Library/Application Support/com.mitchellh.ghostty/config.ghostty'

[ -f "$source_file" ] || fail 'tracked Ghostty config source is missing'
actual_settings=$(grep -vE '^[[:space:]]*(#|$)' "$source_file") \
  || fail 'tracked Ghostty config has no noncomment assignments'
duplicate_keys=$(printf '%s\n' "$actual_settings" \
  | sed -E 's/[[:space:]]*=.*$//' | LC_ALL=C sort | uniq -d)
[ -z "$duplicate_keys" ] || fail "duplicate Ghostty keys: $duplicate_keys"
expected_count=0
while IFS= read -r setting; do
  expected_count=$((expected_count + 1))
  count=$(printf '%s\n' "$actual_settings" | grep -Fxc -- "$setting")
  assert_eq 1 "$count"
done <<'EOF'
font-size = 18
cursor-style = block
cursor-style-blink = false
cursor-color = #d1329b
shell-integration-features = no-cursor
EOF
actual_count=$(printf '%s\n' "$actual_settings" | grep -c .)
assert_eq "$expected_count" "$actual_count"

generation=$(nix build --impure --no-link --print-out-paths \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activationPackage')
home_files=$(readlink -e "$generation/home-files")
[ -n "$home_files" ] || fail 'Home Manager home-files path could not be resolved'
[[ "$home_files" == *-home-manager-files ]] \
  || fail 'resolved home-files is not a Home Manager files tree'
generated="$home_files/$relative"
backup_extension=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.backupFileExtension')
assert_eq backup "$backup_extension"
force=$(nix eval --impure \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.file."Library/Application Support/com.mitchellh.ghostty/config.ghostty".force')
assert_eq false "$force"
[ -L "$generated" ] || fail 'Home Manager did not generate the Ghostty config as a link'
[ -f "$generated" ] || fail 'Home Manager generated the Ghostty config without content'
cmp -s "$source_file" "$generated" \
  || fail 'generated Ghostty config differs from the tracked source'

link_script=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activation.linkGeneration.data' \
  | grep -oE '/nix/store/[^"[:space:]]+-link' | head -1)
[ -x "$link_script" ] || fail 'Home Manager link helper is unavailable'

check_script=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activation.checkLinkTargets.data' \
  | grep -oE '/nix/store/[^"[:space:]]+' | head -1)
[ -f "$check_script" ] || fail 'Home Manager collision-preflight helper is unavailable'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ghostty-preferences-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

run_links() {
  local home=$1
  HOME="$home" HOME_MANAGER_BACKUP_EXT=backup "$link_script" "$home_files" \
    "$home_files/$relative" >/dev/null
}

run_preflight() {
  local home=$1
  HOME="$home" HOME_MANAGER_BACKUP_EXT=backup bash "$check_script" "$home_files" \
    "$home_files/$relative"
}

assert_managed_link() {
  local target=$1
  [ -L "$target" ] || fail "expected $target to be a generation link"
  assert_eq "$generated" "$(readlink "$target")"
  cmp -s "$source_file" "$target" \
    || fail "linked Ghostty config differs from the tracked source"
}

# Absent target: publish the generation link without creating a backup.
absent_home="$TMP/absent-home"
mkdir -p "$absent_home"
run_links "$absent_home"
assert_managed_link "$absent_home/$relative"
[ ! -e "$absent_home/$relative.backup" ] \
  || fail 'absent Ghostty config created an unexpected backup'

# Empty regular file: preserve the empty inode as .backup, then link.
empty_home="$TMP/empty-home"
empty_target="$empty_home/$relative"
mkdir -p "$(dirname "$empty_target")"
: > "$empty_target"
empty_inode=$(file_inode "$empty_target")
run_links "$empty_home"
assert_managed_link "$empty_target"
[ -f "$empty_target.backup" ] || fail 'empty Ghostty config was not preserved as a backup'
[ ! -s "$empty_target.backup" ] || fail 'empty Ghostty backup was not empty'
assert_eq "$empty_inode" "$(file_inode "$empty_target.backup")"
run_links "$empty_home"
assert_managed_link "$empty_target"
[ ! -s "$empty_target.backup" ] || fail 'repeated empty-file link changed the backup'
assert_eq "$empty_inode" "$(file_inode "$empty_target.backup")"

# Differing regular file: preserve the live bytes, then link.
changed_home="$TMP/changed-home"
changed_target="$changed_home/$relative"
mkdir -p "$(dirname "$changed_target")"
printf 'local ghostty change\n' > "$changed_target"
changed_inode=$(file_inode "$changed_target")
run_links "$changed_home"
assert_managed_link "$changed_target"
assert_eq 'local ghostty change' "$(cat "$changed_target.backup")"
assert_eq "$changed_inode" "$(file_inode "$changed_target.backup")"
run_links "$changed_home"
assert_managed_link "$changed_target"
assert_eq 'local ghostty change' "$(cat "$changed_target.backup")"
assert_eq "$changed_inode" "$(file_inode "$changed_target.backup")"

# Identical regular file: still back up, then link.
identical_home="$TMP/identical-home"
identical_target="$identical_home/$relative"
mkdir -p "$(dirname "$identical_target")"
cp "$source_file" "$identical_target"
identical_inode=$(file_inode "$identical_target")
run_links "$identical_home"
assert_managed_link "$identical_target"
cmp -s "$source_file" "$identical_target.backup" \
  || fail 'identical Ghostty config changed during migration'
assert_eq "$identical_inode" "$(file_inode "$identical_target.backup")"
run_links "$identical_home"
assert_managed_link "$identical_target"
cmp -s "$source_file" "$identical_target.backup" \
  || fail 'repeated identical-file link changed the preserved backup'
assert_eq "$identical_inode" "$(file_inode "$identical_target.backup")"

# An older managed-generation symlink updates to a distinct newer tree
# without a new backup. Seed ownership with the canonical *-home-manager-files
# path shape used by Home Manager preflight.
old_home_files=$(nix build --impure --no-link --print-out-paths --expr "$(cat <<'NIX'
let
  flake = builtins.getFlake (toString ./.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
pkgs.runCommand "home-manager-files" { } ''
  mkdir -p "$out/Library/Application Support/com.mitchellh.ghostty"
  printf '%s\n' 'old generation ghostty' > "$out/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
''
NIX
)")
old_generated="$old_home_files/$relative"
[ -f "$old_generated" ] || fail 'prior managed Ghostty generation is missing'
[[ "$old_home_files" == *-home-manager-files ]] \
  || fail 'prior generation is not a Home Manager files tree'
[ "$old_home_files" != "$home_files" ] \
  || fail 'prior managed generation is not distinct from the current files tree'
cmp -s "$source_file" "$old_generated" \
  && fail 'prior managed Ghostty generation did not use different bytes'

managed_home="$TMP/managed-home"
managed_target="$managed_home/$relative"
mkdir -p "$(dirname "$managed_target")"
printf 'first live ghostty\n' > "$managed_target.backup"
ln -s "$old_generated" "$managed_target"
assert_eq "$old_generated" "$(readlink "$managed_target")"
assert_eq 'old generation ghostty' "$(cat "$managed_target")"
backup_inode=$(file_inode "$managed_target.backup")
run_preflight "$managed_home" \
  || fail 'collision preflight rejected a managed generation link'
run_links "$managed_home"
assert_managed_link "$managed_target"
[ "$old_generated" != "$(readlink "$managed_target")" ] \
  || fail 'managed Ghostty link did not move to the new generation'
assert_eq 'first live ghostty' "$(cat "$managed_target.backup")"
assert_eq "$backup_inode" "$(file_inode "$managed_target.backup")"
[ ! -L "$managed_target.backup" ] \
  || fail 'managed generation update backed up the previous symlink'

# Collision preflight rejects a differing regular file when .backup exists.
collision_home="$TMP/collision-home"
collision_target="$collision_home/$relative"
mkdir -p "$(dirname "$collision_target")"
printf 'live collision\n' > "$collision_target"
printf 'existing backup\n' > "$collision_target.backup"
if run_preflight "$collision_home"; then
  fail 'collision preflight accepted a differing regular file with an existing backup'
fi
assert_eq 'live collision' "$(cat "$collision_target")"
assert_eq 'existing backup' "$(cat "$collision_target.backup")"
[ ! -L "$collision_target" ] || fail 'collision preflight replaced a blocked regular file'

# Collision preflight rejects a differing unmanaged symlink.
unmanaged_home="$TMP/unmanaged-home"
unmanaged_target="$unmanaged_home/$relative"
unmanaged_source="$TMP/unmanaged-config.ghostty"
mkdir -p "$(dirname "$unmanaged_target")"
printf 'unmanaged ghostty\n' > "$unmanaged_source"
ln -s "$unmanaged_source" "$unmanaged_target"
if run_preflight "$unmanaged_home"; then
  fail 'collision preflight accepted a differing unmanaged symlink'
fi
[ -L "$unmanaged_target" ] || fail 'collision preflight replaced an unmanaged symlink'
assert_eq "$unmanaged_source" "$(readlink "$unmanaged_target")"
assert_eq 'unmanaged ghostty' "$(cat "$unmanaged_target")"
[ ! -e "$unmanaged_target.backup" ] \
  || fail 'collision preflight created a backup for an unmanaged symlink'

printf 'ok - Home Manager Ghostty links, backups, and collision preflight\n'
