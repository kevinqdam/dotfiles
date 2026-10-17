#!/usr/bin/env bash
# Behavioral contract for conservative global Pi settings seeding.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MATERIALIZER="$SCRIPT_DIR/agents/materialize-pi-settings.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pi-settings-config-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
stopped_pid=

cleanup() {
  if [ -n "$stopped_pid" ]; then
    kill -CONT "$stopped_pid" >/dev/null 2>&1 || true
    kill "$stopped_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'pi-settings-config.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

inode_of() {
  if inode=$(stat -f '%i' "$1" 2>/dev/null); then
    printf '%s\n' "$inode"
  else
    stat -c '%i' "$1"
  fi
}

wait_until_stopped() {
  pid=$1
  attempt=0
  while [ "$attempt" -lt 200 ]; do
    state=$(ps -o state= -p "$pid" 2>/dev/null || true)
    case "$state" in
      *T*) return 0 ;;
    esac
    kill -0 "$pid" 2>/dev/null || fail 'settings materializer exited before test hook'
    sleep 0.01
    attempt=$((attempt + 1))
  done
  fail 'settings materializer did not reach test hook'
}

start_hooked() {
  hook=$1
  agent_dir=$2
  PI_SETTINGS_CONFIG_TEST_HOOK="$hook" python3 -u "$MATERIALIZER" "$agent_dir" \
    >/dev/null 2>&1 &
  stopped_pid=$!
  wait_until_stopped "$stopped_pid"
}

finish_hooked_failure() {
  message=$1
  kill -CONT "$stopped_pid"
  if wait "$stopped_pid"; then
    stopped_pid=
    fail "$message"
  fi
  stopped_pid=
}

PI_PKG=${PI_TEST_PACKAGE_DIR:-}
if [ -z "$PI_PKG" ]; then
  PI_HOMEBREW=/opt/homebrew/bin/pi
  [ -x "$PI_HOMEBREW" ] || fail "Pi package path is unavailable; set PI_TEST_PACKAGE_DIR"
  PI_PKG=$(python3 - "$PI_HOMEBREW" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).resolve()
for parent in p.parents:
    candidate = parent / "libexec/lib/node_modules/@earendil-works/pi-coding-agent"
    if (candidate / "dist/core/settings-manager.js").is_file():
        print(candidate)
        break
else:
    sys.exit(1)
PY
  ) || fail "Pi settings consumer package is unavailable from $PI_HOMEBREW"
fi
[ -f "$PI_PKG/dist/core/settings-manager.js" ] || fail "Pi settings consumer is unavailable: $PI_PKG"

settings_consumer() {
  agent_dir=$1
  node --input-type=module - "$PI_PKG" "$agent_dir" "$TMP" <<'EOF'
import assert from "node:assert/strict";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [piPkg, agentDir, cwd] = process.argv.slice(2);
const { SettingsManager } = await import(
  pathToFileURL(join(piPkg, "dist/core/settings-manager.js")).href
);
const manager = SettingsManager.create(cwd, agentDir);
const settings = manager.settings;
console.log(JSON.stringify({
  defaultProvider: settings.defaultProvider,
  defaultModel: settings.defaultModel,
  defaultThinkingLevel: settings.defaultThinkingLevel,
  packages: settings.packages,
  enabledModels: settings.enabledModels,
  extensions: settings.extensions,
  skills: settings.skills,
  promptTemplates: settings.promptTemplates,
  themes: settings.themes,
}));
EOF
}

[ ! -L "$MATERIALIZER" ] || fail 'settings materializer is a symlink'
grep -Fq 'home.activation.piSettings = lib.hm.dag.entryAfter [ "piPackages" ]' \
  "$SCRIPT_DIR/home.nix" || fail 'Pi settings seeder is not ordered after Pi package convergence'
# shellcheck disable=SC2016
grep -Fq '${./agents/materialize-pi-settings.py}' "$SCRIPT_DIR/home.nix" \
  || fail 'Home Manager activation does not invoke the Pi settings seeder'
if grep -Fq 'home.file.".pi/agent/settings.json"' "$SCRIPT_DIR/home.nix"; then
  fail 'Pi settings must not be Home Manager-linked'
fi
python3 - "$MATERIALIZER" <<'PY'
from pathlib import Path
import sys
compile(Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")
PY

fresh="$TMP/fresh/.pi/agent"
python3 "$MATERIALIZER" "$fresh" >/dev/null
[ -f "$fresh/settings.json" ] || fail 'fresh settings.json was not created'
[ ! -L "$fresh/settings.json" ] || fail 'fresh settings.json is a symlink'
jq -e '
  .defaultProvider == "openai-codex"
  and .defaultModel == "gpt-6.1-sol"
  and .defaultThinkingLevel == "high"
  and (keys == ["defaultModel", "defaultProvider", "defaultThinkingLevel"])
' "$fresh/settings.json" >/dev/null || fail 'fresh settings do not contain exactly the Sol 6.1/high defaults'
consumer=$(settings_consumer "$fresh" | tail -n 1)
assert_eq '{"defaultProvider":"openai-codex","defaultModel":"gpt-6.1-sol","defaultThinkingLevel":"high"}' \
  "$(printf '%s' "$consumer" | jq -c '{defaultProvider,defaultModel,defaultThinkingLevel}')"
fresh_snapshot="$TMP/fresh.snapshot"
cp "$fresh/settings.json" "$fresh_snapshot"
fresh_inode=$(inode_of "$fresh/settings.json")
python3 "$MATERIALIZER" "$fresh" >/dev/null
cmp -s "$fresh_snapshot" "$fresh/settings.json" || fail 'repeated fresh seeding changed settings bytes'
assert_eq "$fresh_inode" "$(inode_of "$fresh/settings.json")"

preserved="$TMP/preserved/.pi/agent"
mkdir -p "$preserved"
cat > "$preserved/settings.json" <<'EOF'
{
  "theme": "light",
  "packages": [
    {"source": "captain-package", "extensions": [], "skills": [], "promptTemplates": [], "themes": []}
  ],
  "enabledModels": [],
  "extensions": [],
  "skills": [],
  "promptTemplates": [],
  "themes": [],
  "defaultThinkingLevel": "medium"
}
EOF
python3 "$MATERIALIZER" "$preserved" >/dev/null
jq -e '
  .defaultProvider == "openai-codex"
  and .defaultModel == "gpt-6.1-sol"
  and .defaultThinkingLevel == "medium"
  and .theme == "light"
  and .packages == [{source:"captain-package",extensions:[],skills:[],promptTemplates:[],themes:[]}]
  and .enabledModels == []
  and .extensions == [] and .skills == [] and .promptTemplates == [] and .themes == []
' "$preserved/settings.json" >/dev/null || fail 'model defaults changed unrelated settings or explicit thinking'
consumer=$(settings_consumer "$preserved" | tail -n 1)
assert_eq '{"defaultProvider":"openai-codex","defaultModel":"gpt-6.1-sol","defaultThinkingLevel":"medium","packages":[{"source":"captain-package","extensions":[],"skills":[],"promptTemplates":[],"themes":[]}],"enabledModels":[],"extensions":[],"skills":[],"promptTemplates":[],"themes":[]}' \
  "$(printf '%s' "$consumer" | jq -c '{defaultProvider,defaultModel,defaultThinkingLevel,packages,enabledModels,extensions,skills,promptTemplates,themes}')"

sol_missing_effort="$TMP/sol-missing-effort/.pi/agent"
mkdir -p "$sol_missing_effort"
printf '{"defaultProvider":"openai-codex","defaultModel":"gpt-6.1-sol","theme":"dark"}\n' \
  > "$sol_missing_effort/settings.json"
python3 "$MATERIALIZER" "$sol_missing_effort" >/dev/null
jq -e '.defaultProvider == "openai-codex" and .defaultModel == "gpt-6.1-sol" and .defaultThinkingLevel == "high" and .theme == "dark"' \
  "$sol_missing_effort/settings.json" >/dev/null || fail 'missing Sol thinking default was not seeded'
[ "$(settings_consumer "$sol_missing_effort" | tail -n 1 | jq -r .defaultThinkingLevel)" = high ] \
  || fail 'Pi settings consumer did not load the seeded Sol thinking level'

custom="$TMP/custom/.pi/agent"
mkdir -p "$custom"
cat > "$custom/settings.json" <<'EOF'
{
  "defaultProvider": "anthropic",
  "defaultModel": "operator-model",
  "defaultThinkingLevel": "low",
  "packages": [],
  "enabledModels": []
}
EOF
custom_snapshot="$TMP/custom.snapshot"
cp "$custom/settings.json" "$custom_snapshot"
custom_inode=$(inode_of "$custom/settings.json")
python3 "$MATERIALIZER" "$custom" >/dev/null
cmp -s "$custom_snapshot" "$custom/settings.json" || fail 'complete custom route was rewritten'
assert_eq "$custom_inode" "$(inode_of "$custom/settings.json")"

for partial in provider-only model-only; do
  partial_dir="$TMP/$partial/.pi/agent"
  mkdir -p "$partial_dir"
  if [ "$partial" = provider-only ]; then
    printf '{"defaultProvider":"openai-codex","theme":"dark"}\n' > "$partial_dir/settings.json"
  else
    printf '{"defaultModel":"gpt-6.1-sol","theme":"dark"}\n' > "$partial_dir/settings.json"
  fi
  snapshot="$TMP/$partial.snapshot"
  cp "$partial_dir/settings.json" "$snapshot"
  before_inode=$(inode_of "$partial_dir/settings.json")
  diagnostic="$TMP/$partial.stderr"
  python3 "$MATERIALIZER" "$partial_dir" >/dev/null 2>"$diagnostic"
  grep -Fq 'partial default model route found; leaving settings unchanged' "$diagnostic" \
    || fail "$partial ambiguous route did not produce an actionable diagnostic"
  cmp -s "$snapshot" "$partial_dir/settings.json" || fail "$partial ambiguous route was rewritten"
  assert_eq "$before_inode" "$(inode_of "$partial_dir/settings.json")"
done

other_route="$TMP/other-route/.pi/agent"
mkdir -p "$other_route"
printf '{"defaultProvider":"openai-codex","defaultModel":"gpt-6-luna"}\n' \
  > "$other_route/settings.json"
other_snapshot="$TMP/other-route.snapshot"
cp "$other_route/settings.json" "$other_snapshot"
other_inode=$(inode_of "$other_route/settings.json")
python3 "$MATERIALIZER" "$other_route" >/dev/null
cmp -s "$other_snapshot" "$other_route/settings.json" || fail 'complete non-Sol route was rewritten'
assert_eq "$other_inode" "$(inode_of "$other_route/settings.json")"

for malformed in invalid-json duplicate-key non-object; do
  target="$TMP/$malformed/.pi/agent"
  mkdir -p "$target"
  case "$malformed" in
    invalid-json) printf '{/* comments are not valid Pi settings */}\n' > "$target/settings.json" ;;
    duplicate-key) printf '{"theme":"dark","theme":"light"}\n' > "$target/settings.json" ;;
    non-object) printf '[]\n' > "$target/settings.json" ;;
  esac
  snapshot="$TMP/$malformed.snapshot"
  cp "$target/settings.json" "$snapshot"
  before_inode=$(inode_of "$target/settings.json")
  if python3 "$MATERIALIZER" "$target" >/dev/null 2>&1; then
    fail "$malformed settings were accepted"
  fi
  cmp -s "$snapshot" "$target/settings.json" || fail "$malformed settings were rewritten"
  assert_eq "$before_inode" "$(inode_of "$target/settings.json")"
done

symlink="$TMP/symlink/.pi/agent"
mkdir -p "$symlink"
printf '{"theme":"dark"}\n' > "$TMP/outside-settings.json"
ln -s "$TMP/outside-settings.json" "$symlink/settings.json"
if python3 "$MATERIALIZER" "$symlink" >/dev/null 2>&1; then
  fail 'settings symlink did not fail closed'
fi
[ -L "$symlink/settings.json" ] || fail 'settings symlink was replaced'
assert_eq '{"theme":"dark"}' "$(cat "$TMP/outside-settings.json")"

hard_linked="$TMP/hard-linked/.pi/agent"
mkdir -p "$hard_linked"
printf '{"theme":"dark"}\n' > "$TMP/hard-linked-source.json"
ln "$TMP/hard-linked-source.json" "$hard_linked/settings.json"
if python3 "$MATERIALIZER" "$hard_linked" >/dev/null 2>&1; then
  fail 'hard-linked settings file did not fail closed'
fi
assert_eq 2 "$(python3 - "$hard_linked/settings.json" <<'PY'
import os
import sys
print(os.stat(sys.argv[1]).st_nlink)
PY
)"

race="$TMP/race/.pi/agent"
mkdir -p "$race"
start_hooked before-publish "$race"
printf '{"theme":"captain-won"}\n' > "$race/settings.json"
finish_hooked_failure 'concurrent settings creation did not fail closed'
assert_eq captain-won "$(jq -r .theme "$race/settings.json")"

replacement="$TMP/replacement/.pi/agent"
mkdir -p "$replacement"
printf '{"theme":"dark"}\n' > "$replacement/settings.json"
printf '{"theme":"captain-won"}\n' > "$TMP/replacement-candidate.json"
start_hooked before-replace "$replacement"
mv "$TMP/replacement-candidate.json" "$replacement/settings.json"
finish_hooked_failure 'concurrent settings replacement did not fail closed'
assert_eq captain-won "$(jq -r .theme "$replacement/settings.json")"

parent_race="$TMP/parent-race/.pi/agent"
outside="$TMP/outside-agent"
mkdir -p "$parent_race" "$outside"
start_hooked after-agent-open "$parent_race"
mv "$TMP/parent-race/.pi/agent" "$TMP/parent-race/.pi/original-agent"
ln -s "$outside" "$parent_race"
finish_hooked_failure 'Pi agent directory replacement did not fail closed'
[ ! -e "$outside/settings.json" ] || fail 'directory replacement escaped through settings.json'

printf 'ok - Pi global settings defaults, preservation, consumer loading, and fail-closed publication\n'
