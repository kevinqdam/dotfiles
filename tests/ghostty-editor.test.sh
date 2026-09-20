#!/usr/bin/env bash
# Behavioral contract for the scoped Ghostty terminal-Vim config alias.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'ghostty-editor.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

GHOSTTY_BIN='/Applications/Ghostty.app/Contents/MacOS/ghostty'
EXPECTED_ALIAS="alias ghostty-config='env VISUAL=vim EDITOR=vim ${GHOSTTY_BIN} +edit-config'"

session_variables=$(nix eval --impure --json \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.sessionVariables')
jq -e 'has("VISUAL") | not' <<<"$session_variables" >/dev/null \
  || fail 'Home Manager still exports a global VISUAL editor'
jq -e 'has("EDITOR") | not' <<<"$session_variables" >/dev/null \
  || fail 'Home Manager still exports a global EDITOR editor'

zsh_session_variables=$(nix eval --impure --json \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.programs.zsh.sessionVariables')
jq -e 'has("VISUAL") | not' <<<"$zsh_session_variables" >/dev/null \
  || fail 'zsh sessionVariables exports a global VISUAL editor'
jq -e 'has("EDITOR") | not' <<<"$zsh_session_variables" >/dev/null \
  || fail 'zsh sessionVariables exports a global EDITOR editor'

init_content=$(nix eval --impure --raw \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.programs.zsh.initContent')
printf '%s\n' "$init_content" | grep -Fqx "$EXPECTED_ALIAS" \
  || fail 'evaluated zsh initContent omitted the ghostty-config alias'

generation=$(nix build --impure --no-link --print-out-paths \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.activationPackage')
generated_zshrc="$generation/home-files/.zshrc"
[ -f "$generated_zshrc" ] || fail 'Home Manager did not generate .zshrc'
grep -Fq "$EXPECTED_ALIAS" "$generated_zshrc" \
  || fail 'generated .zshrc omitted the ghostty-config alias'
if grep -E '^[[:space:]]*(export[[:space:]]+)?(EDITOR|VISUAL)=' "$generated_zshrc"; then
  fail 'generated .zshrc exports a global editor'
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ghostty-editor-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fake_ghostty="$TMP/ghostty"
child_record="$TMP/child.env"
parent_record="$TMP/parent.env"
cat > "$fake_ghostty" <<EOF
#!/usr/bin/env bash
{
  printf 'visual:%s\n' "\${VISUAL-unset}"
  printf 'editor:%s\n' "\${EDITOR-unset}"
  printf 'argc:%s\n' "\$#"
  printf 'arg:%s\n' "\$@"
} > '$child_record'
EOF
chmod +x "$fake_ghostty"

test_alias=${EXPECTED_ALIAS//$GHOSTTY_BIN/$fake_ghostty}
[ "$test_alias" != "$EXPECTED_ALIAS" ] \
  || fail 'test did not substitute the fake Ghostty executable'
printf '%s\n' "$test_alias" > "$TMP/alias.zsh"
printf 'ghostty-config\n' > "$TMP/invoke.zsh"
cat > "$TMP/run.zsh" <<EOF
setopt aliases
source '$TMP/alias.zsh'
source '$TMP/invoke.zsh'
printf 'parent-visual:%s\n' "\${VISUAL-unset}" > '$parent_record'
printf 'parent-editor:%s\n' "\${EDITOR-unset}" >> '$parent_record'
EOF

run_alias() {
  rm -f "$child_record" "$parent_record"
  env -u VISUAL -u EDITOR "$@" zsh --no-rcs --no-global-rcs "$TMP/run.zsh"
  [ -f "$child_record" ] || fail 'fake Ghostty executable was not invoked'
  [ -f "$parent_record" ] || fail 'parent editor environment was not recorded'
}

assert_child_vim_edit_config() {
  assert_eq $'visual:vim\neditor:vim\nargc:1\narg:+edit-config' "$(cat "$child_record")"
}

run_alias
assert_child_vim_edit_config
assert_eq $'parent-visual:unset\nparent-editor:unset' "$(cat "$parent_record")"

run_alias VISUAL=emacs EDITOR=nano
assert_child_vim_edit_config
assert_eq $'parent-visual:emacs\nparent-editor:nano' "$(cat "$parent_record")"

printf 'ok - Ghostty config alias scopes Vim without global editor exports\n'
