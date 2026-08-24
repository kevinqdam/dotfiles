#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONVERGER="$SCRIPT_DIR/agents/converge-firstmate-homebrew"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-homebrew-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

calls="$TMP/calls"
brew="$TMP/brew"

# The single-quoted lines are emitted into the fake executable for expansion there.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  ': "${CALLS:?}"' \
  '[ "${HOMEBREW_FORCE_API_AUTO_UPDATE:-}" = 1 ]' \
  '[ "${HOMEBREW_NO_AUTO_UPDATE:-}" = 1 ]' \
  '[ "${HOMEBREW_NO_INSTALL_CLEANUP:-}" = 1 ]' \
  '[ "${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}" = 1 ]' \
  'printf "%s\\n" "$*" >> "$CALLS"' > "$brew"
chmod +x "$brew"

CALLS="$calls" "$CONVERGER" "$brew" "$(id -un)"

expected='upgrade --greedy --no-ask pi-coding-agent herdr antigravity-cli'
actual=$(cat "$calls")
if [ "$actual" != "$expected" ]; then
  printf 'firstmate-homebrew-convergence.test.sh: expected %s, got %s\n' \
    "$expected" "$actual" >&2
  exit 1
fi

printf 'ok - Firstmate Homebrew convergence targets only Pi, Herdr, and greedy Agy\n'
