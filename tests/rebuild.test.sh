#!/usr/bin/env bash
# Behavioral contract for explicit Homebrew upgrade mode in rebuild.sh.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rebuild-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

worktree="$TMP/worktree"
home="$TMP/home"
bin_dir="$TMP/bin"
log="$TMP/log"
state="$TMP/state"
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

cat > "$worktree/agents/converge-firstmate-homebrew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
: "${STATE:?}"
printf 'upgrade-helper %s\n' "$*" >> "$LOG"
: > "$STATE/helper-ran"
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
if [ "${EXPECT_UPGRADE:-0}" = 1 ] && [ ! -e "$STATE/helper-ran" ]; then
  printf 'Nix rebuild started before the requested Homebrew upgrade\n' >&2
  exit 97
fi
EOF

cat > "$bin_dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${LOG:?}"
printf 'sudo %s\n' "$*" >> "$LOG"
EOF
chmod +x "$bin_dir/git" "$bin_dir/nix" "$bin_dir/sudo"

LOG="$log"
STATE="$state"
export LOG STATE
path_with_fakes="$bin_dir:$PATH"
run_rebuild() {
  expected_upgrade=$1
  shift
  HOME="$home" PATH="$path_with_fakes" EXPECT_UPGRADE="$expected_upgrade" \
    "$worktree/rebuild.sh" "$@"
}

# Plain rebuilds retain the normal declarative build and activation flow but do
# not invoke the mutable package-upgrade helper.
: > "$log"
rm -f "$state/helper-ran"
run_rebuild 0
assert_eq $'git add .\nnix build .#darwinConfigurations.macbook.system\nsudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook\nsetup-harnesses' "$(cat "$log")"
[ ! -e "$state/helper-ran" ] || fail 'plain rebuild unexpectedly ran Homebrew upgrades'

# --upgrade runs the explicit helper before staging and the normal Nix rebuild.
: > "$log"
rm -f "$state/helper-ran"
run_rebuild 1 --upgrade
assert_eq $'upgrade-helper /opt/homebrew/bin/brew '"$(id -un)"$'\ngit add .\nnix build .#darwinConfigurations.macbook.system\nsudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook\nsetup-harnesses' "$(cat "$log")"
[ -e "$state/helper-ran" ] || fail 'upgrade mode did not run Homebrew upgrades'

# Flags outside the explicit interface fail before any rebuild side effect.
: > "$log"
if run_rebuild 0 --unknown >/dev/null 2>"$TMP/unknown.err"; then
  fail 'unknown rebuild flag was accepted'
fi
[ ! -s "$log" ] || fail 'unknown flag caused a rebuild side effect'
grep -Fq 'usage:' "$TMP/unknown.err" || fail 'unknown flag did not print usage'

printf 'ok - plain rebuild, explicit upgrade ordering, and unknown-flag rejection\n'
