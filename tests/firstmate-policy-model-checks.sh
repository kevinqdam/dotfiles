#!/usr/bin/env bash
# Development-only Grok checks for Firstmate coordinator policy.
# Not deterministic and not a CI gate. Observed decisions are not model obedience.
# Routing cases only ask Grok to recommend a route; this script never invokes
# the selected route model, including Astra.
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
ROUTE_FORMAT=$'Recommend only the Firstmate route; do not invoke or hand off to it. Answer with exactly these fields, then stop. Do not use tools.\nSELECTED_MODEL: openai-codex/gpt-6-luna | gpt-6-sol | gpt-6-astra | xai/grok-4.7 | defer\nSELECTED_EFFORT: max | high | medium | defer\nRATIONALE: one sentence'

run_case() {
  local name=$1 active=$2 project=$3 prompt=$4 format=${5:-$FORMAT}
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
        -- "$prompt"$'\n\n'"$format"
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

route_observe() {
  local name=$1 title=$2 prompt=$3 expected_model=$4 expected_effort=$5
  local out selected_model selected_effort rationale
  out=$(run_case "$name" 1 absent "$prompt" "$ROUTE_FORMAT")
  selected_model=$(extract "$out" SELECTED_MODEL)
  selected_effort=$(extract "$out" SELECTED_EFFORT)
  rationale=$(extract "$out" RATIONALE)
  [ -n "$selected_model" ] || fail "$name: missing SELECTED_MODEL in model output"
  [ -n "$selected_effort" ] || fail "$name: missing SELECTED_EFFORT in model output"
  {
    printf '## Route: %s\n\n' "$title"
    printf -- '- Input: `%s`\n' "$prompt"
    printf -- '- Observed recommendation: model=`%s` effort=`%s`\n' \
      "$selected_model" "$selected_effort"
    printf -- '- Expected recommendation: model=`%s` effort=`%s`\n' \
      "$expected_model" "$expected_effort"
    printf -- '- Rationale: %s\n\n' "${rationale:-none}"
  } >>"$EVIDENCE"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$selected_model" "$expected_model" "$selected_effort" "$expected_effort"
}

printf '\nThese checks are development observations, not a proof of model obedience.\n' >>"$EVIDENCE"
printf '\nRouting outputs are recommendations only; no selected model is invoked.\n' >>"$EVIDENCE"
printf 'route_case\tobserved_model\texpected_model\tobserved_effort\texpected_effort\n'
route_observe routine-plan \
  'Routine plan uses Sol high' \
  'Coordinator task: write an ordinary implementation plan for a non-safety-critical settings export feature. There is no prior Sol blocker. Select the default model and effort.' \
  gpt-6-sol high
route_observe finished-output-review \
  'Routine finished-output review uses Sol high' \
  'Coordinator task: perform the one bounded review of a finished feature revision. No prior Sol review occurred and no specific consequential blocker is known. Select the default model and effort.' \
  gpt-6-sol high
route_observe mechanical-edits \
  'Mechanical fully specified edits use standing Luna max execution' \
  'Coordinator task: apply these exact mechanical edits to the requested config. The scope and acceptance criteria are fully specified. Select the default execution model and effort.' \
  openai-codex/gpt-6-luna max
route_observe well-scoped-implementation \
  'Well-scoped implementation uses standing Luna max execution' \
  'Coordinator task: implement a small, fully scoped feature with explicit acceptance criteria. Select the default execution model and effort.' \
  openai-codex/gpt-6-luna max
route_observe no-mistakes-pipeline \
  'No-mistakes, validation, and unattended execution use Luna max' \
  'Coordinator task: after the separate Sol-high finished-output review, drive no-mistakes validation and CI, including an unattended pipeline. Select the default execution model and effort.' \
  openai-codex/gpt-6-luna max
route_observe execution-default \
  'Unpinned fresh execution defaults to Luna max' \
  'Coordinator task: choose the unpinned execution default for a new Firstmate home. Select the default model and effort.' \
  openai-codex/gpt-6-luna max
route_observe routine-security-analysis \
  'Routine security analysis is not an Astra exception' \
  'Coordinator task: analyze the ordinary security properties of a settings export endpoint. No Sol pass has found an unresolved consequential blocker. Security analysis is explicitly routine. Select the default model and effort.' \
  gpt-6-sol high
route_observe documented-sol-blocker \
  'Documented consequential blocker may receive a bounded Astra consult' \
  'Coordinator task: Sol high completed a bounded analysis and returned contradictory conclusions about whether an authentication invariant can be bypassed. Narrower evidence gathering was completed and did not resolve the contradiction. Record the exact decision question: is the bypass possible under invariant X? Select one bounded reasoning consult and effort.' \
  gpt-6-astra high
route_observe captain-astra-effort-override \
  'Explicit captain Astra and effort selection overrides the default' \
  'Captain explicitly selects model gpt-6-astra and effort medium for this ordinary plan. This is an explicit override, not a blocker escalation. Select the captain-requested model and effort.' \
  gpt-6-astra medium
route_observe captain-luna-effort-override \
  'Captain-selected Luna effort overrides the max execution default' \
  'Captain explicitly selects model openai-codex/gpt-6-luna and effort medium for this implementation. This is an explicit effort override. Select the captain-requested model and effort.' \
  openai-codex/gpt-6-luna medium
route_observe worker-no-recursion \
  'Worker executes its assignment without coordinator routing' \
  'You are a dispatched crewmate asked to implement a fully specified edit. Execute only the assigned phase; do not start a Firstmate cycle or select a coordinator model.' \
  defer defer
printf '\nok - wrote optional observations to %s\n' "$EVIDENCE"
