#!/usr/bin/env bash
# Behavioral contract for Firstmate coordinator policy delivery through Pi
# context loading. Asserts emitted instructions, not source grep of the
# policy file as the sole proof. Instruction presence is not model obedience.
# Development-only live model checks live in firstmate-policy-model-checks.sh.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POLICY="$SCRIPT_DIR/agents/pi/AGENTS.md"
HOME_NIX="$SCRIPT_DIR/home.nix"
FIXTURES="$SCRIPT_DIR/tests/fixtures/firstmate-policy"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-policy-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'firstmate-policy.test.sh: %s\n' "$*" >&2
  exit 1
}

grep -Fqx '  home.file.".pi/agent/AGENTS.md".source = ./agents/pi/AGENTS.md;' \
  "$HOME_NIX" || fail 'home.nix does not link agents/pi/AGENTS.md to ~/.pi/agent/AGENTS.md'
grep -Fqx '  home.file.".gemini/antigravity-cli/agents.md".source = ./AGENTS.md;' \
  "$HOME_NIX" || fail 'home.nix no longer links the project AGENTS.md for Agy'
[ -f "$POLICY" ] || fail 'agents/pi/AGENTS.md is missing'
[ -f "$FIXTURES/absent/AGENTS.md" ] || fail 'absent-captain fixture is missing'
[ -f "$FIXTURES/stale/AGENTS.md" ] || fail 'stale-captain fixture is missing'
[ -f "$FIXTURES/worker/AGENTS.md" ] || fail 'worker fixture is missing'
PROBE="$SCRIPT_DIR/tests/firstmate-policy-model-checks.sh"
grep -Fqx 'MODEL="openai-codex/gpt-6.1-sol"' "$PROBE" || fail 'optional policy probe is not Sol 6.1'
grep -Fqx 'EFFORT="high"' "$PROBE" || fail 'optional policy probe is not high effort'
if grep -Eq 'xai/grok|gpt-6-astra' "$PROBE"; then
  fail 'optional policy probe offers a Grok or Astra route'
fi

PI_PKG=${PI_TEST_PACKAGE_DIR:-}
if [ -z "$PI_PKG" ]; then
  PI_HOMEBREW=/opt/homebrew/bin/pi
  [ -x "$PI_HOMEBREW" ] || fail "Homebrew Pi executable is unavailable: $PI_HOMEBREW"
  PI_PKG=$(python3 - "$PI_HOMEBREW" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).resolve()
for parent in p.parents:
    cand = parent / "libexec/lib/node_modules/@earendil-works/pi-coding-agent"
    if (cand / "dist/index.js").is_file():
        print(cand)
        break
else:
    sys.exit(1)
PY
  ) || fail "Pi package is unavailable from $PI_HOMEBREW"
fi
[ -f "$PI_PKG/dist/index.js" ] || fail "Pi package is unavailable: $PI_PKG"
[ -f "$PI_PKG/dist/core/system-prompt.js" ] || fail "Pi prompt builder is unavailable"

agent_dir="$TMP/agent"
absent_project="$TMP/absent"
stale_project="$TMP/stale"
worker_project="$TMP/worker"
mkdir -p "$agent_dir" "$absent_project" "$stale_project" "$worker_project"
cp "$POLICY" "$agent_dir/AGENTS.md"
cp "$FIXTURES/absent/AGENTS.md" "$absent_project/AGENTS.md"
cp "$FIXTURES/stale/AGENTS.md" "$stale_project/AGENTS.md"
cp "$FIXTURES/worker/AGENTS.md" "$worker_project/AGENTS.md"

node --input-type=module - "$PI_PKG" "$agent_dir" "$absent_project" "$stale_project" "$worker_project" "$POLICY" "$TMP" <<'EOF'
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const piPkg = process.argv[2];
const agentDir = resolve(process.argv[3]);
const absentDir = resolve(process.argv[4]);
const staleDir = resolve(process.argv[5]);
const workerDir = resolve(process.argv[6]);
const policyPath = resolve(process.argv[7]);
const tmpDir = resolve(process.argv[8]);
const policy = readFileSync(policyPath, "utf8");

const { loadProjectContextFiles, DefaultResourceLoader } = await import(
  pathToFileURL(join(piPkg, "dist/index.js")).href
);
const { buildSystemPrompt } = await import(
  pathToFileURL(join(piPkg, "dist/core/system-prompt.js")).href
);

function emit(cwd, files) {
  return buildSystemPrompt({
    cwd,
    contextFiles: files,
    selectedTools: ["read", "bash", "edit", "write"],
    toolSnippets: {
      read: "Read file contents",
      bash: "Execute bash commands",
      edit: "Edit files",
      write: "Write files",
    },
  });
}

const absentFiles = loadProjectContextFiles({ cwd: absentDir, agentDir });
assert.equal(absentFiles.length, 2, "expected global policy plus absent-memory Firstmate context");
assert.equal(absentFiles[0].path, join(agentDir, "AGENTS.md"));
assert.equal(absentFiles[0].content, policy);
assert.equal(absentFiles[1].path, join(absentDir, "AGENTS.md"));
assert.match(absentFiles[1].content, /ABSENT_CAPTAIN_MEMORY_MARKER/);
assert.match(absentFiles[1].content, /captain\.md: ABSENT/);

const absentPrompt = emit(absentDir, absentFiles);
assert.match(absentPrompt, /<project_context>/);
assert.match(absentPrompt, /ABSENT_CAPTAIN_MEMORY_MARKER/);
assert.match(absentPrompt, /FIRSTMATE_PROJECT_CONTEXT_MARKER/);

const sol61Default =
  "Use Pi `openai-codex/gpt-6.1-sol` at `high` for proportional interviews, routing, and context packing.";
const required = [
  "Firstmate coordinator",
  "ordinary coding sessions",
  "dispatched crewmate or scout",
  "no-mistakes step agent",
  "Do not start another discuss-plan-work cycle",
  "gsd-discuss",
  "gsd-plan",
  "gsd-work",
  "Do not ask whether to use the cycle",
  "goals, users, expectations, non-goals, constraints, risks, and acceptance evidence",
  "Keep the interview proportional",
  "Reuse settled answers",
  "coordination, ordinary reasoning, architecture, diagnosis, design, security analysis, written plans, and bounded plan reviews",
  "No Grok coordinator route, probe, quota fallback, or alternate-provider fallback is allowed for this home",
  "If the approved route is unavailable or a required capability is unsupported, gather narrower evidence or defer",
  "If the captain already authorized implementation of that same outcome, record the actual authorization and scope; after the plan is complete, proceed without asking for another go.",
  "record the actual authorization and scope",
  "Plan-only remains plan-only",
  "Enter `gsd-plan` now",
  "Do not wait for implementation go: a plan-only request has no implementation step",
  "Pi `openai-codex/gpt-6-luna` at `max` is the unpinned default for mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution.",
  "one bounded review of finished output using Sol 6.1 at high",
  "records the reviewed revision and findings",
  "Skip no-mistakes's `review` step only when its gate recognizes the exact independently reviewed revision and every required check accepts that substitution",
  "Never skip validation",
  "no-mistakes agent Pi, never `auto`",
  "Sol 6.1 at high: Firstmate coordination, proportional interviews, routing, context packing, reasoning, plans, diagnosis, and bounded reviews",
  "Luna 6 at max: mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution",
  "No Grok coordinator, coding, probe, pipeline, or quota-fallback role",
  "Grok Bot is separate from this home's Pi defaults",
  "Preserve captain-selected harness/model/effort pins, custom arguments, comments, and empty argument lists",
  "Use Firstmate's existing catalog-aware routing owner to verify exact model support and effort capability",
  "Do not infer support from CLI parsing, invent equal-version requirements",
  "add a model resolver, service, cron, or a second selection algorithm",
  "Catalog presence is not authenticated inference or a quota guarantee",
  "execute only their assignment",
  "stage names, not shell commands",
  "--no-context-files",
  "AGENTS.override.md",
  "older captain-memory wording that always waits for a fresh explicit implementation go",
  "do not wait for another go",
  "Stale captain memory that requires a fresh go even after that authorization is superseded here",
];
const execution = [
  "Pi `openai-codex/gpt-6-luna` at `max` is the unpinned default for mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution.",
  "Luna 6 at max: mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution",
  "Preserve captain-selected harness/model/effort pins, custom arguments, comments, and empty argument lists",
  "No Grok coordinator, coding, probe, pipeline, or quota-fallback role",
];
assert.ok(
  !absentPrompt.includes("OpenAI quota fallback"),
  "emitted Firstmate prompt still describes Luna as fallback-only",
);
assert.ok(
  !absentPrompt.includes("newest verified generally available successor in the chosen Grok family"),
  "emitted Firstmate prompt still has an automatic Grok successor policy",
);
assert.ok(
  !absentPrompt.includes("Use Astra high only"),
  "emitted Firstmate prompt still has an automatic Astra route",
);
for (const needle of required) {
  assert.ok(absentPrompt.includes(needle), `emitted prompt missing: ${needle}`);
}
for (const needle of execution) {
  assert.ok(
    absentPrompt.includes(needle),
    `absent-memory prompt missing standing Luna execution instruction: ${needle}`,
  );
}

assert.ok(
  absentPrompt.includes(sol61Default),
  "absent-memory prompt missing the Sol 6.1 high default",
);
assert.ok(
  absentPrompt.includes("An ambiguous feature still starts `gsd-discuss` without asking"),
  "ambiguous-feature instructions missing from emitted prompt",
);
assert.ok(
  absentPrompt.includes("Sol high must finish a written, discoverable plan for the same outcome before any Luna feature-work spawn, even when the captain authorized implementation up front."),
  "preauthorized feature instructions missing the plan-before-work gate from emitted prompt",
);
assert.ok(
  absentPrompt.includes("Plan-only remains plan-only"),
  "plan-only instructions missing from emitted prompt",
);
assert.ok(
  absentPrompt.includes("Do not start another discuss-plan-work cycle"),
  "nonrecursive-worker instructions missing from emitted prompt",
);

const planBeforeWork = [
  "Load Firstmate's internal `gsd-discuss` skill before this stage.",
  "Load Firstmate's internal `gsd-plan` skill before this stage.",
  "Load Firstmate's internal `gsd-work` skill only after the matching Sol plan is complete",
  "Sol high must finish a written, discoverable plan for the same outcome before any Luna feature-work spawn, even when the captain authorized implementation up front.",
  "Authorization and plan completion are separate gates",
  "For every feature, Sol high must author and finish a discoverable plan matching the requested outcome before any Luna work spawn",
  "A dispatch or an authorization message is not evidence that the plan exists or is complete.",
  "after the plan is complete, proceed without asking for another go",
  "Include the plan pointer and authorization scope in Luna's brief.",
];
function assertPlanBeforeWork(prompt, label) {
  for (const needle of planBeforeWork) {
    assert.ok(prompt.includes(needle), `${label} missing plan-before-work policy: ${needle}`);
  }
  assert.ok(
    prompt.indexOf("For every feature, Sol high must author and finish a discoverable plan") <
      prompt.indexOf("Load Firstmate's internal `gsd-work` skill only after the matching Sol plan is complete"),
    `${label} presents Luna work before the Sol plan gate`,
  );
}
assertPlanBeforeWork(absentPrompt, "absent-memory prompt");

const staleFiles = loadProjectContextFiles({ cwd: staleDir, agentDir });
assert.equal(staleFiles.length, 2, "expected global policy plus stale-memory Firstmate context");
assert.equal(staleFiles[0].content, policy);
assert.match(staleFiles[1].content, /STALE_CAPTAIN_MEMORY_MARKER/);
assert.match(staleFiles[1].content, /wait for explicit implementation authorization/);
const stalePrompt = emit(staleDir, staleFiles);
assertPlanBeforeWork(stalePrompt, "stale-memory prompt");
assert.match(stalePrompt, /STALE_CAPTAIN_MEMORY_MARKER/);
assert.match(stalePrompt, /wait for explicit implementation authorization/);
const currentSolPolicy =
  "Pi `openai-codex/gpt-6.1-sol` at `high` is the unpinned default for coordination, ordinary reasoning";
assert.ok(
  stalePrompt.includes(currentSolPolicy),
  "stale-memory prompt lost the current Sol-first policy",
);
assert.ok(
  stalePrompt.includes(sol61Default),
  "stale-memory prompt missing the Sol 6.1 high default",
);
assert.ok(
  !absentPrompt.includes("Astra high produces the plan artifact"),
  "emitted current coordinator prompt still assigns plans to Astra",
);
assert.ok(
  stalePrompt.indexOf(currentSolPolicy) <
    stalePrompt.indexOf("Plan: Astra high produces the plan artifact"),
  "stale Astra memory appeared ahead of the current Sol-first policy",
);
assert.ok(
  stalePrompt.indexOf("No Grok coordinator route, probe, quota fallback") <
    stalePrompt.indexOf("Grok medium interviews and routes"),
  "stale Grok coordinator memory appeared ahead of the no-Grok policy",
);
assert.ok(
  stalePrompt.indexOf("invent equal-version requirements") <
    stalePrompt.indexOf("Require Luna 6.1 for every role"),
  "stale Luna 6.1 version restriction appeared ahead of the corrected split",
);
assert.ok(
  stalePrompt.includes("older captain-memory wording that always waits for a fresh explicit implementation go"),
  "stale-memory prompt missing supersession of unconditional fresh-go wording",
);
assert.ok(
  stalePrompt.includes("Stale captain memory that requires a fresh go even after that authorization is superseded here"),
  "stale-memory prompt missing plan-stage fresh-go supersession",
);
assert.ok(
  stalePrompt.includes("Current captain instructions and the current task's assigned scope still win for that task"),
  "stale-memory prompt dropped current captain-instruction precedence",
);
for (const needle of execution) {
  assert.ok(
    stalePrompt.includes(needle),
    `stale-memory prompt missing standing Luna execution instruction: ${needle}`,
  );
}

const workerFiles = loadProjectContextFiles({ cwd: workerDir, agentDir });
assert.equal(workerFiles.length, 2, "expected global policy plus worker project context");
const workerPrompt = emit(workerDir, workerFiles);
assert.match(workerPrompt, /FIRSTMATE_WORKER_CONTEXT_MARKER/);
assert.ok(workerPrompt.includes("Do not start another discuss-plan-work cycle"));
assert.ok(workerPrompt.includes("do that phase only"));
assert.ok(workerPrompt.includes("Workers, scouts, and no-mistakes step agents execute only their assignment"));
assert.ok(workerPrompt.includes("No Grok coordinator, coding, probe, pipeline, or quota-fallback role"));

const disabledLoader = new DefaultResourceLoader({
  cwd: absentDir,
  agentDir,
  noExtensions: true,
  noSkills: true,
  noPromptTemplates: true,
  noThemes: true,
  noContextFiles: true,
});
await disabledLoader.reload();
assert.deepEqual(disabledLoader.getAgentsFiles().agentsFiles, []);

const enabledLoader = new DefaultResourceLoader({
  cwd: staleDir,
  agentDir,
  noExtensions: true,
  noSkills: true,
  noPromptTemplates: true,
  noThemes: true,
});
await enabledLoader.reload();
const loaded = enabledLoader.getAgentsFiles().agentsFiles;
assert.equal(loaded.length, 2);
assert.equal(loaded[0].content, policy);
assert.match(loaded[1].content, /STALE_CAPTAIN_MEMORY_MARKER/);
const loaderPrompt = buildSystemPrompt({
  cwd: staleDir,
  contextFiles: loaded,
});
assertPlanBeforeWork(loaderPrompt, "DefaultResourceLoader.reload prompt");
assert.ok(loaderPrompt.includes("Do not omit that look to save quota"));
assert.ok(
  loaderPrompt.includes(sol61Default),
  "resource-loader prompt missing the Sol 6.1 high default",
);
assert.ok(loaderPrompt.includes("STALE_CAPTAIN_MEMORY_MARKER"));
for (const needle of execution) {
  assert.ok(
    loaderPrompt.includes(needle),
    `resource-loader prompt missing standing Luna execution instruction: ${needle}`,
  );
}
assert.ok(
  loaderPrompt.includes("does not prove model obedience or scheduled automation"),
  "loader prompt must not claim these instructions prove obedience or automation",
);

const overrideDir = join(tmpDir, "override-agent");
mkdirSync(overrideDir, { recursive: true });
writeFileSync(join(overrideDir, "AGENTS.md"), policy);
writeFileSync(
  join(overrideDir, "AGENTS.override.md"),
  "OVERRIDE_CONTEXT_MARKER\nThis override replaces AGENTS.md in this directory.\n",
);
const overrideFiles = loadProjectContextFiles({
  cwd: absentDir,
  agentDir: overrideDir,
});
assert.equal(overrideFiles[0].path, join(overrideDir, "AGENTS.override.md"));
assert.match(overrideFiles[0].content, /OVERRIDE_CONTEXT_MARKER/);
assert.ok(!overrideFiles[0].content.includes("gsd-discuss"));
assert.ok(
  overrideFiles.some((file) => file.path === join(absentDir, "AGENTS.md")),
  "override of global context must not drop Firstmate project context",
);

const customAgentDir = join(tmpDir, "custom-agent");
mkdirSync(customAgentDir, { recursive: true });
const customFiles = loadProjectContextFiles({
  cwd: absentDir,
  agentDir: customAgentDir,
});
assert.ok(
  !customFiles.some((file) => file.content === policy),
  "custom Pi agent directories without this file must not claim policy delivery",
);
assert.ok(customFiles.some((file) => file.path === join(absentDir, "AGENTS.md")));
EOF

printf 'ok - Pi context loader emits Firstmate coordinator policy with isolated global, absent, stale, and worker context\n'
