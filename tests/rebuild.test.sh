#!/usr/bin/env bash
# Behavioral contract for explicit Homebrew upgrade mode in rebuild.sh.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONVERGER="$SCRIPT_DIR/agents/converge-firstmate-homebrew"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rebuild-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

worktree="$TMP/worktree"
home="$TMP/home"
bin_dir="$TMP/bin"
log="$TMP/log"
calls="$TMP/brew-calls"
state="$TMP/state"
brew="$bin_dir/brew"
mkdir -p "$worktree/agents" "$home" "$bin_dir" "$state"
cp "$SCRIPT_DIR/rebuild.sh" "$worktree/rebuild.sh"
chmod +x "$worktree/rebuild.sh"
ln -s "$worktree" "$home/.dotfiles"

fail() {
  printf 'rebuild.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

# Use the production convergence helper with an executable fake Homebrew. The
# fake models Homebrew's installer-manual Logi Tune failure, so accidentally
# including it in the automated command fails before the Nix rebuild.
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
for package in "${@:4}"; do
  if [ "$package" = logitune ]; then
    printf 'Error: Not upgrading 1 installer manual cask\n' >&2
    exit 1
  fi
done

expected='upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini grok-bot iterm2 raycast superwhisper tailscale-app visual-studio-code'
if [ "$*" != "$expected" ]; then
  printf 'unexpected Homebrew command: %s\n' "$*" >&2
  exit 97
fi

: > "$STATE/homebrew-upgrade"
: > "$STATE/raycast-updated"
EOF
chmod +x "$brew"

# The real helper receives the rebuild path's normal Homebrew argument, but the
# fixture routes it to the fake executable above without changing production.
cat > "$worktree/agents/converge-firstmate-homebrew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
: "\${LOG:?}"
printf 'upgrade-helper %s\\n' "\$*" >> "\$LOG"
exec "$CONVERGER" "$brew" "\$2"
EOF
chmod +x "$worktree/agents/converge-firstmate-homebrew"

cat > "$worktree/agents/setup-harnesses" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'setup-harnesses\n' >> "$LOG"
EOF
chmod +x "$worktree/agents/setup-harnesses"

cat > "$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'git %s\n' "$*" >> "$LOG"
EOF

cat > "$bin_dir/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
: "${STATE:?}"
printf 'nix %s\n' "$*" >> "$LOG"
if [ "${EXPECT_UPGRADE:-0}" = 1 ]; then
  [ -e "$STATE/homebrew-upgrade" ] || {
    printf 'Nix rebuild started before the requested Homebrew upgrade\n' >&2
    exit 97
  }
  [ -e "$STATE/raycast-updated" ] || {
    printf 'Nix rebuild did not follow the targeted Homebrew upgrade\n' >&2
    exit 98
  }
fi
EOF

cat > "$bin_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'sudo %s\n' "$*" >> "$LOG"
EOF
chmod +x "$bin_dir/git" "$bin_dir/nix" "$bin_dir/sudo"

path_with_fakes="$bin_dir:$PATH"
run_rebuild() {
  expected_upgrade=$1
  shift
  HOME="$home" PATH="$path_with_fakes" EXPECT_UPGRADE="$expected_upgrade" \
    LOG="$log" CALLS="$calls" STATE="$state" \
    "$worktree/rebuild.sh" "$@"
}

# Plain rebuilds retain the normal declarative build and activation flow but do
# not invoke the mutable package-upgrade helper.
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade" "$state/raycast-updated"
run_rebuild 0
assert_eq $'git add .\nnix build .#darwinConfigurations.macbook.system\nsudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook\nsetup-harnesses' "$(cat "$log")"
[ ! -e "$state/homebrew-upgrade" ] || fail 'plain rebuild unexpectedly ran Homebrew upgrades'
[ ! -s "$calls" ] || fail 'plain rebuild unexpectedly invoked Homebrew'

# --upgrade runs the production helper before staging and the normal Nix
# rebuild. A manual cask that Homebrew would reject cannot stop the rebuild
# because it is absent from the explicit automated invocation.
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade" "$state/raycast-updated"
if ! run_rebuild 1 --upgrade; then
  fail 'installer-manual Logi Tune prevented the Nix rebuild'
fi
expected_upgrade=$'upgrade-helper /opt/homebrew/bin/brew '"$(id -un)"$'\nbrew upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini grok-bot iterm2 raycast superwhisper tailscale-app visual-studio-code\ngit add .\nnix build .#darwinConfigurations.macbook.system\nsudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook\nsetup-harnesses'
assert_eq "$expected_upgrade" "$(cat "$log")"
assert_eq 'upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini grok-bot iterm2 raycast superwhisper tailscale-app visual-studio-code' "$(cat "$calls")"
[ -e "$state/homebrew-upgrade" ] || fail 'upgrade mode did not complete Homebrew upgrades'
[ -e "$state/raycast-updated" ] || fail 'upgrade mode did not upgrade Raycast'

# Flags outside the explicit interface fail before any rebuild side effect.
: > "$log"
: > "$calls"
rm -f "$state/homebrew-upgrade" "$state/raycast-updated"
if run_rebuild 0 --unknown >/dev/null 2>"$TMP/unknown.err"; then
  fail 'unknown rebuild flag was accepted'
fi
[ ! -s "$log" ] || fail 'unknown flag caused a rebuild side effect'
[ ! -s "$calls" ] || fail 'unknown flag invoked Homebrew'
[ ! -e "$state/homebrew-upgrade" ] || fail 'unknown flag ran Homebrew upgrades'
grep -Fq 'usage:' "$TMP/unknown.err" || fail 'unknown flag did not print usage'

printf 'ok - plain rebuild, manual-cask-safe upgrade ordering, Raycast upgrade, and unknown-flag rejection\n'
