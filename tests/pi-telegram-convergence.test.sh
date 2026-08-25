#!/usr/bin/env bash
# Behavioral contract for the pinned Pi package convergence helper.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONVERGER="$SCRIPT_DIR/agents/converge-pi-telegram"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pi-telegram-convergence-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

bin_dir="$TMP/bin"
agent_dir="$TMP/agent"
calls="$TMP/calls"
pi="$bin_dir/pi"
runtime_bin="$TMP/restricted-bin"
mkdir -p "$bin_dir" "$agent_dir" "$runtime_bin"
# Mirror Home Manager's allowlisted activation PATH: required Nix tools are
# available, while /usr/bin is intentionally absent so bare awk is masked.
for runtime_tool in cat dirname jq mkdir; do
  ln -s "$(command -v "$runtime_tool")" "$runtime_bin/$runtime_tool"
done
: > "$calls"

fail() {
  printf 'pi-telegram-convergence.test.sh: %s\n' "$*" >&2
  exit 1
}

[ -x /usr/bin/awk ] || fail 'macOS system awk is unavailable for the activation contract'
[ ! -e "$runtime_bin/awk" ] || fail 'restricted activation fixture unexpectedly exposes awk'

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

cat > "$pi" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${PI_CODING_AGENT_DIR:?}"
: "${CALLS:?}"

state="$PI_CODING_AGENT_DIR/package-source"
manifest="$PI_CODING_AGENT_DIR/installed/package.json"

case "${1:-}" in
  list)
    if [ -f "$state" ]; then
      printf 'User packages:\n  %s\n' "$(cat "$state")"
      if [ -f "$manifest" ]; then
        printf '    %s\n' "$PI_CODING_AGENT_DIR/installed"
      fi
    else
      printf 'No packages installed.\n'
    fi
    ;;
  install)
    [ "${2:-}" = 'npm:@llblab/pi-telegram@0.39.2' ] || exit 97
    printf '%s\n' "$*" >> "$CALLS"
    mkdir -p "$(dirname "$manifest")"
    printf '%s\n' 'npm:@llblab/pi-telegram@0.39.2' > "$state"
    printf '%s\n' '{"name":"@llblab/pi-telegram","version":"0.39.2"}' > "$manifest"
    ;;
  *)
    exit 98
    ;;
esac
EOF
chmod +x "$pi"

run_converger() {
  PATH="$runtime_bin" CALLS="$calls" \
    /bin/bash "$CONVERGER" "$pi" "$agent_dir"
}

# A fresh agent directory installs exactly the reviewed source and creates no
# Telegram setup or connector state.
existing_extension="$agent_dir/existing-extension.ts"
printf '%s\n' 'existing extension' > "$existing_extension"
run_converger
assert_eq 'install npm:@llblab/pi-telegram@0.39.2' "$(cat "$calls")"
jq -e '.version == "0.39.2"' "$agent_dir/installed/package.json" >/dev/null
[ -e "$existing_extension" ] || fail 'existing Pi extension was removed'
[ ! -e "$agent_dir/telegram.json" ] || fail 'Telegram configuration was created by convergence'

# A second activation is a no-op when the exact source and installed version
# are already present.
run_converger
assert_eq 'install npm:@llblab/pi-telegram@0.39.2' "$(cat "$calls")"

# A stale configured source and package are repaired to the pinned version.
printf '%s\n' 'npm:@llblab/pi-telegram@0.39.1' > "$agent_dir/package-source"
printf '%s\n' '{"name":"@llblab/pi-telegram","version":"0.39.1"}' > "$agent_dir/installed/package.json"
run_converger
assert_eq $'install npm:@llblab/pi-telegram@0.39.2\ninstall npm:@llblab/pi-telegram@0.39.2' "$(cat "$calls")"
jq -e '.version == "0.39.2"' "$agent_dir/installed/package.json" >/dev/null
[ -e "$existing_extension" ] || fail 'existing Pi extension was removed during repair'

printf 'ok - pinned Pi package install, idempotent repeat, and stale-version repair\n'
