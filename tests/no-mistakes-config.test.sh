#!/usr/bin/env bash
# Behavioral contract for no-mistakes pipeline-agent routing materialization.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MATERIALIZER="$SCRIPT_DIR/agents/materialize-no-mistakes-config.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/no-mistakes-config-test.XXXXXX")
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
  printf 'no-mistakes-config.test.sh: %s\n' "$*" >&2
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
    kill -0 "$pid" 2>/dev/null || fail 'materializer exited before test hook'
    sleep 0.01
    attempt=$((attempt + 1))
  done
  fail 'materializer did not reach test hook'
}

start_hooked() {
  hook=$1
  target_home=$2
  NO_MISTAKES_CONFIG_TEST_HOOK="$hook" python3 -u "$MATERIALIZER" "$target_home" \
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

routing_json() {
  /usr/bin/ruby -ryaml -rjson -e '
    path = ARGV[0]
    doc = YAML.load_file(path)
    doc = {} if doc.nil? || doc == false
    abort "root is not a mapping" unless doc.is_a?(Hash)
    override = doc["agent_args_override"]
    override = {} unless override.is_a?(Hash)
    print JSON.generate(
      "agent" => doc["agent"],
      "pi_args" => override["pi"],
      "codex_args" => override["codex"],
      "ci_timeout" => doc["ci_timeout"],
      "auto_fix" => doc["auto_fix"],
      "session_reuse" => doc["session_reuse"],
      "log_level" => doc["log_level"],
      "keys" => doc.keys.map(&:to_s)
    )
  ' "$1"
}

assert_approved_routing() {
  file=$1
  json=$(routing_json "$file")
  assert_eq 'pi' "$(printf '%s\n' "$json" | jq -r .agent)"
  assert_eq '["--model","xai/grok-4.6","--thinking","high"]' \
    "$(printf '%s\n' "$json" | jq -c .pi_args)"
}

[ ! -L "$MATERIALIZER" ] || fail 'materializer source is a symlink'

fresh="$TMP/fresh"
python3 "$MATERIALIZER" "$fresh" >/dev/null
[ -f "$fresh/config.yaml" ] || fail 'missing config.yaml'
[ ! -L "$fresh/config.yaml" ] || fail 'created config.yaml is a symlink'
assert_approved_routing "$fresh/config.yaml"
fresh_json=$(routing_json "$fresh/config.yaml")
printf '%s\n' "$fresh_json" | jq -e '.keys == ["agent","agent_args_override"]' \
  >/dev/null || fail 'fresh config was not limited to the approved routing keys'

populated="$TMP/populated"
mkdir -p "$populated"
cat > "$populated/config.yaml" <<'EOF'
# no-mistakes global configuration
# captain comment must survive
agent: auto
ci_timeout: "168h"
session_reuse: true
log_level: info
auto_fix:
  rebase: 3
  lint: 3
  test: 3
  review: 0
  document: 3
  ci: 3
EOF
printf 'daemon-pid\n' > "$populated/daemon.pid"
printf 'sqlite\n' > "$populated/state.sqlite"
python3 "$MATERIALIZER" "$populated" >/dev/null
assert_approved_routing "$populated/config.yaml"
populated_json=$(routing_json "$populated/config.yaml")
assert_eq '168h' "$(printf '%s\n' "$populated_json" | jq -r .ci_timeout)"
assert_eq 'true' "$(printf '%s\n' "$populated_json" | jq -r .session_reuse)"
assert_eq 'info' "$(printf '%s\n' "$populated_json" | jq -r .log_level)"
assert_eq '0' "$(printf '%s\n' "$populated_json" | jq -r .auto_fix.review)"
assert_eq '3' "$(printf '%s\n' "$populated_json" | jq -r .auto_fix.test)"
grep -Fq 'captain comment must survive' "$populated/config.yaml" \
  || fail 'captain comment was not preserved'
assert_eq 'daemon-pid' "$(cat "$populated/daemon.pid")"
assert_eq 'sqlite' "$(cat "$populated/state.sqlite")"

overrides="$TMP/overrides"
mkdir -p "$overrides"
cat > "$overrides/config.yaml" <<'EOF'
agent: claude
ci_timeout: "42h"
agent_args_override:
  codex:
    - --foo
  pi:
    - --model
    - gpt-4.1
EOF
python3 "$MATERIALIZER" "$overrides" >/dev/null
assert_approved_routing "$overrides/config.yaml"
overrides_json=$(routing_json "$overrides/config.yaml")
assert_eq '42h' "$(printf '%s\n' "$overrides_json" | jq -r .ci_timeout)"
assert_eq '["--foo"]' "$(printf '%s\n' "$overrides_json" | jq -c .codex_args)"

commented="$TMP/commented-override"
mkdir -p "$commented"
cat > "$commented/config.yaml" <<'EOF'
agent: auto
ci_timeout: "12h"
agent_args_override: # flags
  codex:
    - --foo
  pi: # grok
    - --model
    - gpt-4.1
EOF
python3 "$MATERIALIZER" "$commented" >/dev/null
assert_approved_routing "$commented/config.yaml"
commented_json=$(routing_json "$commented/config.yaml")
assert_eq '12h' "$(printf '%s\n' "$commented_json" | jq -r .ci_timeout)"
assert_eq '["--foo"]' "$(printf '%s\n' "$commented_json" | jq -c .codex_args)"

already="$TMP/already"
mkdir -p "$already"
cp "$overrides/config.yaml" "$already/config.yaml"
before_inode=$(inode_of "$already/config.yaml")
python3 "$MATERIALIZER" "$already" >/dev/null
assert_approved_routing "$already/config.yaml"
assert_eq "$before_inode" "$(inode_of "$already/config.yaml")"
cmp -s "$overrides/config.yaml" "$already/config.yaml" \
  || fail 'already-correct config was rewritten'

flow="$TMP/flow"
mkdir -p "$flow"
printf 'agent: [codex, claude]\nci_timeout: "9h"\n' > "$flow/config.yaml"
python3 "$MATERIALIZER" "$flow" >/dev/null
assert_approved_routing "$flow/config.yaml"
assert_eq '9h' "$(routing_json "$flow/config.yaml" | jq -r .ci_timeout)"

missing_override="$TMP/missing-override"
mkdir -p "$missing_override"
printf 'agent: pi\nlog_level: debug\n' > "$missing_override/config.yaml"
python3 "$MATERIALIZER" "$missing_override" >/dev/null
assert_approved_routing "$missing_override/config.yaml"
assert_eq 'debug' "$(routing_json "$missing_override/config.yaml" | jq -r .log_level)"

conflict="$TMP/conflict"
mkdir -p "$conflict"
printf 'captain-owned\n' > "$conflict/config-target"
ln -s ./config-target "$conflict/config.yaml"
if python3 "$MATERIALIZER" "$conflict" >/dev/null 2>&1; then
  fail 'symlink conflict did not fail closed'
fi
[ -L "$conflict/config.yaml" ] || fail 'symlink conflict was replaced'
assert_eq './config-target' "$(readlink "$conflict/config.yaml")"
assert_eq 'captain-owned' "$(cat "$conflict/config-target")"

directory_target="$TMP/directory-target"
mkdir -p "$directory_target/config.yaml"
if python3 "$MATERIALIZER" "$directory_target" >/dev/null 2>&1; then
  fail 'directory target did not fail closed'
fi
[ -d "$directory_target/config.yaml" ] || fail 'directory target was replaced'

hard_linked="$TMP/hard-linked"
mkdir -p "$hard_linked"
printf 'agent: auto\n' > "$hard_linked/source"
ln "$hard_linked/source" "$hard_linked/config.yaml"
if python3 "$MATERIALIZER" "$hard_linked" >/dev/null 2>&1; then
  fail 'hard-linked target did not fail closed'
fi
assert_eq 'agent: auto' "$(cat "$hard_linked/config.yaml")"

sequence="$TMP/sequence"
mkdir -p "$sequence"
printf -- '- not: a mapping\n' > "$sequence/config.yaml"
if python3 "$MATERIALIZER" "$sequence" >/dev/null 2>&1; then
  fail 'sequence document did not fail closed'
fi
assert_eq '- not: a mapping' "$(cat "$sequence/config.yaml")"

race="$TMP/race"
mkdir -p "$race"
start_hooked before-publish "$race"
printf 'captain-won\n' > "$race/config.yaml"
finish_hooked_failure 'concurrent target publication did not fail closed'
assert_eq 'captain-won' "$(cat "$race/config.yaml")"

replacement="$TMP/replacement"
mkdir -p "$replacement"
printf 'agent: auto\nci_timeout: "1h"\n' > "$replacement/config.yaml"
printf 'captain-yaml\n' > "$replacement/replacement.yaml"
start_hooked before-replace "$replacement"
mv "$replacement/replacement.yaml" "$replacement/config.yaml"
finish_hooked_failure 'atomic config replacement did not fail closed'
assert_eq 'captain-yaml' "$(cat "$replacement/config.yaml")"

symlink_race="$TMP/symlink-race"
mkdir -p "$symlink_race"
printf 'agent: auto\n' > "$symlink_race/config.yaml"
printf 'live-daemon-state\n' > "$symlink_race/outside"
start_hooked before-replace "$symlink_race"
rm "$symlink_race/config.yaml"
ln -s ./outside "$symlink_race/config.yaml"
finish_hooked_failure 'symlink smash during replace did not fail closed'
[ -L "$symlink_race/config.yaml" ] || fail 'live yaml was not left as a symlink'
assert_eq './outside' "$(readlink "$symlink_race/config.yaml")"
assert_eq 'live-daemon-state' "$(cat "$symlink_race/outside")"

directory_race="$TMP/directory-replacement"
outside_home="$TMP/outside-home"
mkdir -p "$directory_race" "$outside_home"
start_hooked after-home-open "$directory_race"
mv "$directory_race" "$TMP/original-home"
ln -s "$outside_home" "$directory_race"
finish_hooked_failure 'canonical home replacement did not fail closed'
[ ! -e "$outside_home/config.yaml" ] || fail 'directory replacement escaped through config.yaml'

printf 'ok - no-mistakes routing materialization, preservation, and fail-closed contracts\n'
