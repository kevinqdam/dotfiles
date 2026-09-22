#!/usr/bin/env bash
# Development-only Grok checks for Firstmate coordinator policy.
# Not deterministic and not a CI gate. Observed decisions are not model obedience.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POLICY="$SCRIPT_DIR/agents/pi/AGENTS.md"
FIXTURES="$SCRIPT_DIR/tests/fixtures/firstmate-policy"
EVIDENCE="${FIRSTMATE_POLICY_MODEL_CHECK_EVIDENCE:-$SCRIPT_DIR/tests/firstmate-policy-model-check-evidence.md}"
PI_HOMEBREW=/opt/homebrew/bin/pi
AUTH_JSON="${HOME}/.pi/agent/auth.json"
MODEL="xai/grok-4.7"
EFFORT="medium"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-policy-model-checks.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'firstmate-policy-model-checks.sh: %s\n' "$*" >&2
  exit 1
}

[ -x "$PI_HOMEBREW" ] || fail "Homebrew Pi executable is unavailable: $PI_HOMEBREW"
[ -f "$POLICY" ] || fail 'agents/pi/AGENTS.md is missing'
[ -f "$AUTH_JSON" ] || fail 'Pi xAI auth.json is missing; isolated checks need credentials'
[ -f "$FIXTURES/absent/AGENTS.md" ] || fail 'absent-captain fixture is missing'
[ -f "$FIXTURES/stale/AGENTS.md" ] || fail 'stale-captain fixture is missing'
[ -f "$FIXTURES/worker/AGENTS.md" ] || fail 'worker fixture is missing'

agent_dir="$TMP/agent"
mkdir -p "$agent_dir"
cp "$POLICY" "$agent_dir/AGENTS.md"
ln -s "$AUTH_JSON" "$agent_dir/auth.json"

for name in absent stale worker; do
  mkdir -p "$TMP/$name"
  cp "$FIXTURES/$name/AGENTS.md" "$TMP/$name/AGENTS.md"
done

FORMAT=$'Answer with exactly these fields, then stop. Do not use tools.\nSTAGE: gsd-discuss | gsd-plan | gsd-work | assigned-phase | ask-cycle\nWAIT_FOR_GO: yes | no | n/a\nASK_WHETHER_TO_USE_CYCLE: yes | no\nAUTHORITY_RECORDED: yes | no | n/a\nRATIONALE: one sentence'

run_case() {
  local name=$1 active=$2 project=$3 prompt=$4
  local out="$TMP/$name.out"
  local env_active=()
  if [ "$active" = 1 ]; then
    env_active=(FM_FIRSTMATE_ACTIVE=1)
  else
    env_active=(FM_FIRSTMATE_ACTIVE=)
  fi
  (
    cd "$TMP/$project"
    env "${env_active[@]}" \
      PI_CODING_AGENT_DIR="$agent_dir" \
      PI_SKIP_VERSION_CHECK=1 \
      "$PI_HOMEBREW" -p --approve --no-session --no-extensions --no-skills --no-tools \
        --model "$MODEL" --thinking "$EFFORT" \
        -- "$prompt"$'\n\n'"$FORMAT"
  ) >"$out" 2>"$TMP/$name.err" || fail "pi failed for $name (see $TMP/$name.err)"
  printf '%s' "$out"
}

extract() {
  local file=$1 field=$2
  tr -d '\r' <"$file" | awk -v field="$field" '
    BEGIN { prefix=field ": " }
    index($0, prefix)==1 {
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  '
}

parent=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
{
  printf '# Firstmate policy development model checks\n\n'
  printf 'Not a deterministic test. These observations do not prove universal model obedience.\n\n'
  printf -- '- Parent revision: `%s`\n' "$parent"
  printf -- '- Model: `%s`\n' "$MODEL"
  printf -- '- Effort: `%s`\n' "$EFFORT"
  printf -- '- Isolated `PI_CODING_AGENT_DIR` with `agents/pi/AGENTS.md` plus a symlink to live `auth.json` (read credentials only).\n'
  printf -- '- Project fixtures: `tests/fixtures/firstmate-policy/{absent,stale,worker}`.\n'
  printf -- '- No live captain-memory overwrite, no activation, no rebuild, no Codex.\n\n'
} >"$EVIDENCE"

observe() {
  local name=$1 title=$2 active=$3 project=$4 prompt=$5 expected_stage=$6 expected_wait=$7 expected_ask=$8 expected_auth=$9
  local out
  out=$(run_case "$name" "$active" "$project" "$prompt")
  local stage wait ask auth rationale
  stage=$(extract "$out" STAGE)
  wait=$(extract "$out" WAIT_FOR_GO)
  ask=$(extract "$out" ASK_WHETHER_TO_USE_CYCLE)
  auth=$(extract "$out" AUTHORITY_RECORDED)
  rationale=$(extract "$out" RATIONALE)
  [ -n "$stage" ] || fail "$name: missing STAGE in model output"
  {
    printf '## %s\n\n' "$title"
    printf -- '- Case: `%s`\n' "$name"
    printf -- '- Coordinator active: `%s`\n' "$active"
    printf -- '- Fixture: `%s`\n' "$project"
    printf -- '- Input:\n\n```\n%s\n```\n\n' "$prompt"
    printf -- '- Observed: STAGE=`%s` WAIT_FOR_GO=`%s` ASK_WHETHER_TO_USE_CYCLE=`%s` AUTHORITY_RECORDED=`%s`\n' \
      "$stage" "$wait" "$ask" "$auth"
    printf -- '- Expected: STAGE=`%s` WAIT_FOR_GO=`%s` ASK_WHETHER_TO_USE_CYCLE=`%s` AUTHORITY_RECORDED=`%s`\n' \
      "$expected_stage" "$expected_wait" "$expected_ask" "$expected_auth"
    printf -- '- Rationale: %s\n\n' "${rationale:-"(none)"}"
  } >>"$EVIDENCE"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$stage" "$expected_stage" "$wait" "$expected_wait" "$ask" "$expected_ask" "$auth" "$expected_auth"
}

printf 'case\tobserved_stage\texpected_stage\tobserved_wait\texpected_wait\tobserved_ask\texpected_ask\tobserved_auth\texpected_auth\n'

observe ambiguous-absent \
  'Ambiguous feature, captain memory absent' \
  1 absent \
  'Captain: we should make onboarding better. Decide the next Firstmate stage only.' \
  gsd-discuss n/a no n/a

observe authorized-absent \
  'Already-authorized outcome, captain memory absent' \
  1 absent \
  'Captain: Implement the dark-mode toggle we already scoped. I authorize implementation of that outcome now: add a user-facing dark mode setting on the settings page. Decide the next Firstmate stage only. Record whether that authorization is enough to proceed.' \
  'gsd-plan|gsd-work' no no yes

observe plan-only-absent \
  'Plan-only request, captain memory absent' \
  1 absent \
  'Captain: Plan only: how should we split the billing service? Do not implement. Decide the next Firstmate stage only.' \
  gsd-plan 'n/a|no' no n/a

observe worker-absent \
  'Dispatched worker, nonrecursive' \
  0 worker \
  'You are a dispatched Firstmate crewmate. Your brief: add the cask "foo" to darwin-configuration.nix homebrew.casks. Execute only the assigned phase. Decide the next Firstmate stage only.' \
  assigned-phase n/a no n/a

observe authorized-stale \
  'Already-authorized outcome, stale captain memory with unconditional fresh-go' \
  1 stale \
  'Captain: Implement the dark-mode toggle we already scoped. I authorize implementation of that outcome now: add a user-facing dark mode setting on the settings page. Stale captain memory in the digest says wait for explicit implementation authorization. Decide the next Firstmate stage only.' \
  'gsd-plan|gsd-work' no no yes

observe ambiguous-stale \
  'Ambiguous feature, stale captain memory that prefers asking about the cycle' \
  1 stale \
  'Captain: we should make onboarding better. Stale captain memory in the digest prefers a discuss-plan-work cycle. Decide the next Firstmate stage only. Do not ask the captain whether to use the cycle.' \
  gsd-discuss n/a no n/a

printf '\nThese checks are development observations, not a proof of model obedience.\n' >>"$EVIDENCE"
printf 'ok - wrote %s\n' "$EVIDENCE"
