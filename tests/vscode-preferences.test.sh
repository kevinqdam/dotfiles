#!/usr/bin/env bash
# Behavioral contract for VS Code preference links and audited extensions.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'vscode-preferences.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

settings_source="$REPO_ROOT/vscode/settings.json"
keybindings_source="$REPO_ROOT/vscode/keybindings.json"
extensions_source="$REPO_ROOT/vscode/extensions.txt"
settings_relative='Library/Application Support/Code/User/settings.json'
keybindings_relative='Library/Application Support/Code/User/keybindings.json'

[ -f "$settings_source" ] || fail 'tracked settings source is missing'
[ -f "$keybindings_source" ] || fail 'tracked keybindings source is missing'
[ -s "$extensions_source" ] || fail 'tracked extension inventory is missing'
[ "$(grep -c '^[^[:space:]]' "$extensions_source")" -eq 71 ] \
  || fail 'tracked extension inventory is incomplete'
if ! LC_ALL=C sort -fu "$extensions_source" | cmp -s - "$extensions_source"; then
  fail 'tracked extension inventory is not unique and sorted'
fi
for extension in \
  pkief.material-icon-theme \
  vscodevim.vim \
  zhuangtongfa.material-theme; do
  grep -Fqx "$extension" "$extensions_source" \
    || fail "tracked extension inventory omitted $extension"
done
for setting in \
  '"workbench.colorTheme": "One Dark Pro"' \
  '"workbench.iconTheme": "material-icon-theme"' \
  '"vim.useSystemClipboard": true' \
  '"vim.cursorStylePerMode.insert": "line-thin"' \
  '"editorCursor.foreground": "#d1329b"' \
  '"terminalCursor.foreground": "#d1329b"'; do
  grep -Fq "$setting" "$settings_source" \
    || fail "tracked settings omitted $setting"
done
grep -Fqx '    "key": "cmd+enter",' "$keybindings_source" \
  || fail 'tracked keybindings omitted cmd+enter override'

# Build the actual Home Manager generation rather than testing only the Nix
# source. Its home-files tree is the materialization input used by rebuild.sh.
generation=$(nix build --impure --no-link --print-out-paths \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activationPackage')
home_files="$generation/home-files"
backup_extension=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.backupFileExtension')
assert_eq backup "$backup_extension"
for relative in "$settings_relative" "$keybindings_relative"; do
  generated="$home_files/$relative"
  [ -L "$generated" ] || fail "Home Manager did not generate $relative as a link"
  [ -f "$generated" ] || fail "Home Manager generated $relative without content"
done
cmp -s "$settings_source" "$home_files/$settings_relative" \
  || fail 'generated settings differ from tracked settings'
cmp -s "$keybindings_source" "$home_files/$keybindings_relative" \
  || fail 'generated keybindings differ from tracked keybindings'

# Exercise Home Manager's real link helper in a disposable HOME. Pre-existing
# regular files are preserved in the configured backup before the generation
# link is published, whether or not their content is identical.
link_script=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activation.linkGeneration.data' \
  | grep -oE '/nix/store/[^"[:space:]]+-link' | head -1)
[ -x "$link_script" ] || fail 'Home Manager link helper is unavailable'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/vscode-preferences-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
home="$TMP/home"
user_dir="$home/Library/Application Support/Code/User"
mkdir -p "$user_dir"
cp "$settings_source" "$user_dir/settings.json"
cp "$keybindings_source" "$user_dir/keybindings.json"

run_links() {
  HOME="$home" HOME_MANAGER_BACKUP_EXT=backup "$link_script" "$home_files" \
    "$home_files/$settings_relative" "$home_files/$keybindings_relative" \
    >/dev/null
}

settings_inode() {
  if stat -c '%i' "$1" >/dev/null 2>&1; then
    stat -c '%i' "$1"
  else
    stat -f '%i' "$1"
  fi
}

before_inode=$(settings_inode "$user_dir/settings.json")
run_links
[ -L "$user_dir/settings.json" ] \
  || fail 'identical live settings were not linked to the generation'
[ -f "$user_dir/settings.json.backup" ] \
  || fail 'identical live settings were not preserved as a backup'
cmp -s "$settings_source" "$user_dir/settings.json" \
  || fail 'linked settings differ from the generation'
cmp -s "$settings_source" "$user_dir/settings.json.backup" \
  || fail 'identical live settings changed during migration'
assert_eq "$before_inode" "$(settings_inode "$user_dir/settings.json.backup")"
run_links
cmp -s "$settings_source" "$user_dir/settings.json" \
  || fail 'repeated link did not remain idempotent'
cmp -s "$settings_source" "$user_dir/settings.json.backup" \
  || fail 'repeated link changed the preserved backup'

changed_home="$TMP/changed-home"
changed_user_dir="$changed_home/Library/Application Support/Code/User"
mkdir -p "$changed_user_dir"
printf 'local settings change\n' > "$changed_user_dir/settings.json"
cp "$keybindings_source" "$changed_user_dir/keybindings.json"
run_changed_links() {
  HOME="$changed_home" HOME_MANAGER_BACKUP_EXT=backup "$link_script" "$home_files" \
    "$home_files/$settings_relative" "$home_files/$keybindings_relative" \
    >/dev/null
}
run_changed_links
[ -L "$changed_user_dir/settings.json" ] \
  || fail 'changed live settings were not linked to the generation'
[ -f "$changed_user_dir/settings.json.backup" ] \
  || fail 'changed live settings were not preserved as a backup'
assert_eq 'local settings change' "$(cat "$changed_user_dir/settings.json.backup")"
cmp -s "$settings_source" "$changed_user_dir/settings.json" \
  || fail 'changed settings link differs from the generation'
run_changed_links
cmp -s "$settings_source" "$changed_user_dir/settings.json" \
  || fail 'repeated changed-file link did not remain idempotent'
assert_eq 'local settings change' "$(cat "$changed_user_dir/settings.json.backup")"

# The extension activation is also run against a fake code CLI. The first run
# installs only missing audited IDs; the second run must be a no-op.
activation=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activation.vscodeExtensions.data')
printf '%s\n' "$activation" | grep -Fq 'extensions.txt' \
  || fail 'extension activation does not consume the tracked inventory'

state="$TMP/extensions"
install_log="$TMP/extension-installs"
head -n 1 "$extensions_source" > "$state"
sed -n '2,$p' "$extensions_source" > "$TMP/expected-installs"
: > "$install_log"
fake_code="$TMP/code"
cat > "$fake_code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${STATE:?}"
: "${INSTALL_LOG:?}"
case "${1:-}" in
  --list-extensions)
    cat "$STATE"
    ;;
  --install-extension)
    [ "$#" -eq 2 ]
    printf '%s\n' "$2" >> "$INSTALL_LOG"
    printf '%s\n' "$2" >> "$STATE"
    ;;
  *)
    printf 'unexpected code invocation: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$fake_code"
activation=${activation//\/opt\/homebrew\/bin\/code/$fake_code}
activation_script="$TMP/activation.sh"
printf '%s\n' "$activation" > "$activation_script"
STATE="$state" INSTALL_LOG="$install_log" bash "$activation_script"
cmp -s "$extensions_source" "$state" \
  || fail 'extension activation did not restore the complete audited inventory'
cmp -s "$TMP/expected-installs" "$install_log" \
  || fail 'extension activation installed an unexpected set of IDs'
STATE="$state" INSTALL_LOG="$install_log" bash "$activation_script"
cmp -s "$extensions_source" "$state" \
  || fail 'repeated extension activation changed the inventory'
cmp -s "$TMP/expected-installs" "$install_log" \
  || fail 'repeated extension activation was not idempotent'

printf 'ok - Home Manager VS Code links, safe migration, complete extension inventory, and idempotence\n'
