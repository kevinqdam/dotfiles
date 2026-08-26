#!/usr/bin/env bash
# Behavioral contract for the explicit Homebrew upgrade boundary.
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
expected='upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini iterm2 logitune raycast superwhisper tailscale-app visual-studio-code'
if [ "$*" != "$expected" ]; then
  printf 'unexpected Homebrew command: %s\n' "$*" >&2
  exit 97
fi

if [ "$MODE" = conflict ]; then
  printf 'Error: It seems there is already a Binary at /opt/homebrew/bin/agy\n' >&2
  exit 1
fi

mkdir -p "$STATE/downloaded" "$STATE/replaced" "$STATE/formulas"
for package in "${@:4}"; do
  case "$package" in
    pi-coding-agent|herdr)
      : > "$STATE/formulas/$package"
      ;;
    antigravity-cli|chatgpt|codex|google-drive|google-chrome|google-gemini|iterm2|logitune|raycast|superwhisper|tailscale-app|visual-studio-code)
      # Model Homebrew downloading a cask payload and replacing its app bundle.
      : > "$STATE/downloaded/$package"
      : > "$STATE/replaced/$package"
      ;;
    *)
      printf 'unexpected package side effect: %s\n' "$package" >&2
      exit 98
      ;;
  esac
done

: > "$STATE/targeted-upgrade"
EOF
chmod +x "$brew"

# A successful upgrade invokes exactly the explicit allowlist. The fake Brew
# rejects every other command and records the download and app-bundle
# replacement side effects for each selected cask.
: > "$calls"
rm -rf "$state"
mkdir -p "$state"
MODE=success CALLS="$calls" STATE="$state" \
  "$CONVERGER" "$brew" "$owner" >"$TMP/success.out" 2>"$TMP/success.err"
assert_eq 'upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini iterm2 logitune raycast superwhisper tailscale-app visual-studio-code' "$(cat "$calls")"
for cask in antigravity-cli chatgpt codex google-drive google-chrome google-gemini iterm2 logitune raycast superwhisper tailscale-app visual-studio-code; do
  [ -e "$state/downloaded/$cask" ] || fail "$cask download was not requested"
  [ -e "$state/replaced/$cask" ] || fail "$cask app replacement was not requested"
done
[ ! -e "$state/downloaded/anaconda" ] || fail 'Anaconda was unexpectedly downloaded'
for formula in blueutil mono mysql mysql-client tcl-tk; do
  [ ! -e "$state/formulas/$formula" ] || fail "$formula was unexpectedly upgraded"
done
[ -e "$state/formulas/pi-coding-agent" ] || fail 'Pi formula was not upgraded'
[ -e "$state/formulas/herdr" ] || fail 'Herdr formula was not upgraded'
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
assert_eq 'upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli chatgpt codex google-drive google-chrome google-gemini iterm2 logitune raycast superwhisper tailscale-app visual-studio-code' "$(cat "$calls")"
grep -Fq 'already a Binary at /opt/homebrew/bin/agy' "$TMP/conflict.err" \
  || fail 'Homebrew conflict diagnostic was not surfaced'
[ ! -e "$state/targeted-upgrade" ] || fail 'failed upgrade changed the fixture'

agy_auto_update=$(cd "$SCRIPT_DIR" && nix eval --raw --no-write-lock-file \
  '.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.sessionVariables.AGY_CLI_DISABLE_AUTO_UPDATE')
assert_eq true "$agy_auto_update"

printf 'ok - explicit greedy Homebrew allowlist, cask replacement side effects, conflict propagation, and exclusions\n'
