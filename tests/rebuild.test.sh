#!/usr/bin/env bash
# Behavioral contract for clone-local rebuild source selection.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rebuild-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

home="$TMP/home"
bin_dir="$TMP/bin"
log="$TMP/log"
calls="$TMP/brew-calls"
state="$TMP/state"
brew="$bin_dir/brew"
mkdir -p "$home" "$bin_dir" "$state" "$TMP/cwd" "$TMP/other"

fail() {
  printf 'rebuild.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

assert_log_exact() {
  expected=$1
  actual=$(cat "$log")
  [ "$expected" = "$actual" ] || {
    printf 'log:\n%s\n' "$actual" >&2
    fail "unexpected stage log"
  }
}

create_fixture() {
  local root=$1
  mkdir -p "$root/agents"
  cp "$SCRIPT_DIR/rebuild.sh" "$root/rebuild.sh"
  chmod +x "$root/rebuild.sh"
  : > "$root/flake.nix"
  cat > "$root/agents/converge-firstmate-homebrew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
: "\${LOG:?}"
printf 'upgrade-helper cwd=%s args=%s\\n' "\$PWD" "\$*" >> "\$LOG"
exec "$SCRIPT_DIR/agents/converge-firstmate-homebrew" "$brew" "\$2"
EOF
  cat > "$root/agents/setup-harnesses" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'setup cwd=%s\n' "$PWD" >> "$LOG"
EOF
  chmod +x "$root/agents/converge-firstmate-homebrew" "$root/agents/setup-harnesses"
}

root="$TMP/clone with spaces"
other_root="$TMP/other-clone"
create_fixture "$root"
create_fixture "$other_root"

cat > "$brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${CALLS:?}"
: "${LOG:?}"
: "${STATE:?}"
[ "${HOMEBREW_FORCE_API_AUTO_UPDATE:-}" = 1 ]
[ "${HOMEBREW_NO_AUTO_UPDATE:-}" = 1 ]
[ "${HOMEBREW_NO_INSTALL_CLEANUP:-}" = 1 ]
[ "${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}" = 1 ]
printf 'brew %s\n' "$*" >> "$LOG"
printf '%s\n' "$*" >> "$CALLS"
expected='upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex ghostty google-drive google-chrome google-gemini grok-bot iterm2 raycast superwhisper tailscale-app visual-studio-code'
[ "$*" = "$expected" ] || {
  printf 'unexpected Homebrew command: %s\n' "$*" >&2
  exit 97
}
: > "$STATE/homebrew-upgrade"
EOF
chmod +x "$brew"

cat > "$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'git cwd=%s args=%s\n' "$PWD" "$*" >> "$LOG"
EOF
cat > "$bin_dir/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'nix cwd=%s args=%s\n' "$PWD" "$*" >> "$LOG"
EOF
cat > "$bin_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'sudo cwd=%s args=%s\n' "$PWD" "$*" >> "$LOG"
EOF
chmod +x "$bin_dir/git" "$bin_dir/nix" "$bin_dir/sudo"

path_with_fakes="$bin_dir:$PATH"
run_rebuild() {
  local script=$1
  local cwd=$2
  shift 2
  (cd "$cwd" && HOME="$home" PATH="$path_with_fakes" \
    LOG="$log" CALLS="$calls" STATE="$state" \
    "$script" "$@")
}

# A direct clone works without ~/.dotfiles and is independent of the caller's cwd.
rm -f "$home/.dotfiles"
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade"
run_rebuild "$root/rebuild.sh" "$TMP/cwd"
assert_log_exact $'git cwd='"$root"$' args=add .\nnix cwd='"$root"$' args=build '"$root"$'#darwinConfigurations.macbook.system\nsudo cwd='"$root"$' args=./result/sw/bin/darwin-rebuild switch --flake '"$root"$'#macbook\nsetup cwd='"$root"
[ ! -e "$home/.dotfiles" ] || fail 'direct clone unexpectedly required ~/.dotfiles'

# The existing interactive alias target remains a valid symlink invocation.
ln -s "$root" "$home/.dotfiles"
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade"
run_rebuild "$home/.dotfiles/rebuild.sh" "$TMP/cwd" --upgrade
assert_log_exact $'upgrade-helper cwd='"$root"$' args=/opt/homebrew/bin/brew '"$(id -un)"$'\nbrew upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex ghostty google-drive google-chrome google-gemini grok-bot iterm2 raycast superwhisper tailscale-app visual-studio-code\ngit cwd='"$root"$' args=add .\nnix cwd='"$root"$' args=build '"$root"$'#darwinConfigurations.macbook.system\nsudo cwd='"$root"$' args=./result/sw/bin/darwin-rebuild switch --flake '"$root"$'#macbook\nsetup cwd='"$root"
[ -e "$home/.dotfiles" ] || fail 'alias target symlink was removed'
[ -e "$state/homebrew-upgrade" ] || fail 'upgrade stage did not run'

# A second direct clone wins over an unrelated existing ~/.dotfiles target.
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade"
run_rebuild "$other_root/rebuild.sh" "$TMP/cwd"
assert_log_exact $'git cwd='"$other_root"$' args=add .\nnix cwd='"$other_root"$' args=build '"$other_root"$'#darwinConfigurations.macbook.system\nsudo cwd='"$other_root"$' args=./result/sw/bin/darwin-rebuild switch --flake '"$other_root"$'#macbook\nsetup cwd='"$other_root"

# Unknown arguments fail before repository or host side effects.
: > "$log"
: > "$calls"
if run_rebuild "$root/rebuild.sh" "$TMP/cwd" --unknown >/dev/null 2>"$TMP/unknown.err"; then
  fail 'unknown flag was accepted'
fi
[ ! -s "$log" ] || fail 'unknown flag caused a side effect'
grep -Fq 'usage:' "$TMP/unknown.err" || fail 'unknown flag did not print usage'
grep -Fqx 'alias nix-rebuild="~/.dotfiles/rebuild.sh"' "$SCRIPT_DIR/zshrc" \
  || fail 'interactive nix-rebuild alias changed'

printf 'ok - direct clone, linked alias, independent clone, absolute flake roots, and argument rejection\n'
