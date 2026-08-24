#!/usr/bin/env bash
# Behavioral contract for the narrow Homebrew activation upgrade boundary.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONVERGER="$SCRIPT_DIR/agents/converge-firstmate-homebrew"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-homebrew-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

bin_dir="$TMP/bin"
mkdir -p "$bin_dir"
calls="$TMP/calls"
state="$TMP/state"
brew="$bin_dir/brew"
owner=$(id -un)

fail() {
  printf 'firstmate-homebrew-convergence.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

cat > "$brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${CALLS:?}"
: "${MODE:?}"
: "${STATE:?}"
[ "${HOMEBREW_FORCE_API_AUTO_UPDATE:-}" = 1 ]
[ "${HOMEBREW_NO_AUTO_UPDATE:-}" = 1 ]
[ "${HOMEBREW_NO_INSTALL_CLEANUP:-}" = 1 ]
[ "${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}" = 1 ]

printf '%s\n' "$*" >> "$CALLS"
expected='upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli'
if [ "$*" != "$expected" ]; then
  printf 'unexpected Homebrew command: %s\n' "$*" >&2
  exit 97
fi

if [ "$MODE" = conflict ]; then
  printf 'Error: It seems there is already a Binary at /opt/homebrew/bin/agy\n' >&2
  exit 1
fi

: > "$STATE/targeted-upgrade"
EOF
chmod +x "$brew"

# A successful activation invokes exactly the targeted upgrade. The fake Brew
# rejects every other command, proving there is no unrelated package change or
# custom Agy package-management path.
: > "$calls"
rm -rf "$state"
mkdir -p "$state"
MODE=success CALLS="$calls" STATE="$state" \
  "$CONVERGER" "$brew" "$owner" >"$TMP/success.out" 2>"$TMP/success.err"
assert_eq 'upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli' "$(cat "$calls")"
[ -e "$state/targeted-upgrade" ] || fail 'targeted upgrade was not completed'
[ ! -s "$TMP/success.err" ] || fail 'successful upgrade emitted unexpected diagnostics'

# Homebrew failures remain failures and retain Homebrew's actionable conflict
# message for a one-time operator repair.
: > "$calls"
rm -rf "$state"
mkdir -p "$state"
if MODE=conflict CALLS="$calls" STATE="$state" \
  "$CONVERGER" "$brew" "$owner" >"$TMP/conflict.out" 2>"$TMP/conflict.err"; then
  fail 'Homebrew conflict was treated as success'
fi
assert_eq 'upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli' "$(cat "$calls")"
grep -Fq 'already a Binary at /opt/homebrew/bin/agy' "$TMP/conflict.err" \
  || fail 'Homebrew conflict diagnostic was not surfaced'
[ ! -e "$state/targeted-upgrade" ] || fail 'failed upgrade changed the fixture'

# Keep the updater opt-out declarative while leaving installation/versioning to
# Homebrew.
grep -Fq 'AGY_CLI_DISABLE_AUTO_UPDATE = "true"' "$SCRIPT_DIR/home.nix" \
  || fail 'Agy auto-update opt-out is missing'
if grep -Eq 'reinstall|--adopt|quarantine|receipt|check_agy|agy_version|outdated' "$CONVERGER"; then
  fail 'convergence script still contains custom Agy package-management logic'
fi

printf 'ok - targeted Homebrew upgrade, conflict propagation, and no unrelated package changes\n'
