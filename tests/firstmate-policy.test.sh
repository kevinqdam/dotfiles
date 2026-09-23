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

const required = [
  "Firstmate coordinator",
  "ordinary coding",
  "dispatched crewmate",
  "no-mistakes step",
  "Do not start another discuss-plan-work cycle",
  "gsd-discuss",
  "gsd-plan",
  "gsd-work",
  "Do not ask whether to use the cycle",
  "goals, users, expectations, non-goals, constraints, risks, and acceptance evidence",
  "scaled to ambiguity",
  "Reuse answers already supplied",
  "Sol high owns ordinary reasoning (including architecture, diagnosis, design, and security analysis), the written plan artifact, and bounded reviews of plans",
  "Use Astra high only when a specific consequential reasoning blocker remains unresolved after a bounded Sol-high pass, or when the captain explicitly selects Astra",
  "the exact decision question",
  "why another normal Sol pass or narrower evidence gathering cannot settle it",
  "An important-sounding label, broad architecture or security category, subjective difficulty, ordinary review, plan stage, quota/cost concern, or Sol outage is not by itself an exception",
  "Gather missing evidence or stay with Sol rather than silently switching",
  "Wait for go before `gsd-work` unless the captain already authorized implementation of that same outcome",
  "Record the actual authorization",
  "Plan-only remains plan-only",
  "Enter `gsd-plan` now",
  "Do not wait for implementation go: a plan-only request has no implementation step",
  "Grok implements, tests, lints, resolves review findings, and drives no-mistakes/CI",
  "one bounded Sol-high review of finished output",
  "records the reviewed revision and findings",
  "The same evidence-gated Astra exception applies to this review",
  "the review stage alone is not grounds for Astra",
  "Never omit that look to save quota",
  "skip no-mistakes's `review` step, not validation",
  "no-mistakes agent as Pi, never `auto`",
  "Sol high: ordinary reasoning, written plans, bounded plan reviews, and one bounded finished-output review per ship",
  "Astra high: one bounded consult only for the documented consequential blocker after Sol",
  "Model and effort are defaults, not pins",
  "explicit captain-selected harness, model, and effort requests take precedence",
  "including Astra or a Pi-based OpenAI quota fallback",
  "No automatic second Sol or Astra loop",
  "not implicit merge permission",
  "execute the assigned phase only",
  "stage names, not shell commands",
  "--no-context-files",
  "AGENTS.override.md",
  "older captain-memory wording that always waits for a fresh explicit implementation go",
  "do not wait for another go",
  "Stale captain memory that requires a fresh go even after that authorization is superseded here",
];
const successor = [
  "Coordinator only",
  "do not apply this rule",
  "newest verified generally available successor in the chosen Grok family",
  "without a fresh upgrade request",
  "chosen harness catalog",
  "Do not guess a latest alias",
  "Keep the current roles and efforts",
  "Preserve explicit pins",
  "existing catalog-aware dispatch policy",
  "Do not add a resolver, service, cron, or a second selection algorithm",
  "passive rebuild, catalog refresh, or unattended daemon does not migrate existing concrete model IDs",
  "Never interrupt an active session or run",
  "does not prove model obedience or scheduled automation",
];
const fallback = [
  "Coordinator only. For an OpenAI quota fallback from Grok that the captain has authorized",
  "prefer the Pi harness with model ID `gpt-6-luna` at effort `max`",
  "provider-qualified Pi CLI selector: `--model openai-codex/gpt-6-luna --thinking max`",
  "Verify that the current Pi catalog lists `gpt-6-luna` under provider `openai-codex` and maps thinking level `max` to `max` before dispatch",
  "catalog availability does not prove quota or successful inference",
  "not an automatic retry or a new default",
  "does not replace Grok-first implementation and validation or the Sol/Astra reasoning and review roles",
  "Explicit captain-selected harness, model, and effort fields each take precedence",
  "honor every explicit field rather than replacing it with the fallback",
  "Preserve operator-owned arguments, comments, empty/custom argument lists, and existing homes",
  "Do not migrate a historical Luna 5.6 or any other concrete model ID",
  "A source policy update takes effect for new work only after rebuild and Pi context reload or a new session",
  "Let active work finish",
  "next safely started, captain-authorized fallback segment",
  "never by interrupting or rerouting an active session or run",
];
assert.ok(
  !policy.includes("openai-codex/gpt-5.6-luna"),
  "global Firstmate policy still names Luna 5.6 as a fallback",
);
for (const needle of required) {
  assert.ok(absentPrompt.includes(needle), `emitted prompt missing: ${needle}`);
}
for (const needle of successor) {
  assert.ok(
    absentPrompt.includes(needle),
    `absent-memory prompt missing successor instruction: ${needle}`,
  );
}
for (const needle of fallback) {
  assert.ok(
    absentPrompt.includes(needle),
    `absent-memory prompt missing OpenAI fallback instruction: ${needle}`,
  );
}

assert.ok(
  absentPrompt.includes("An ambiguous feature still starts `gsd-discuss` without asking"),
  "ambiguous-feature instructions missing from emitted prompt",
);
assert.ok(
  absentPrompt.includes("unless the captain already authorized implementation of that same outcome"),
  "already-authorized instructions missing from emitted prompt",
);
assert.ok(
  absentPrompt.includes("Plan-only remains plan-only"),
  "plan-only instructions missing from emitted prompt",
);
assert.ok(
  absentPrompt.includes("Do not start another discuss-plan-work cycle"),
  "nonrecursive-worker instructions missing from emitted prompt",
);

const staleFiles = loadProjectContextFiles({ cwd: staleDir, agentDir });
assert.equal(staleFiles.length, 2, "expected global policy plus stale-memory Firstmate context");
assert.equal(staleFiles[0].content, policy);
assert.match(staleFiles[1].content, /STALE_CAPTAIN_MEMORY_MARKER/);
assert.match(staleFiles[1].content, /wait for explicit implementation authorization/);
const stalePrompt = emit(staleDir, staleFiles);
assert.match(stalePrompt, /STALE_CAPTAIN_MEMORY_MARKER/);
assert.match(stalePrompt, /wait for explicit implementation authorization/);
const currentSolPolicy =
  "Sol high owns ordinary reasoning (including architecture, diagnosis, design, and security analysis), the written plan artifact, and bounded reviews of plans";
assert.ok(
  stalePrompt.includes(currentSolPolicy),
  "stale-memory prompt lost the current Sol-first policy",
);
assert.ok(
  !policy.includes("Astra high produces the plan artifact"),
  "current coordinator policy still assigns plans to Astra",
);
assert.ok(
  stalePrompt.indexOf(currentSolPolicy) <
    stalePrompt.indexOf("Plan: Astra high produces the plan artifact"),
  "stale Astra memory appeared ahead of the current Sol-first policy",
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
for (const needle of successor) {
  assert.ok(
    stalePrompt.includes(needle),
    `stale-memory prompt missing successor instruction: ${needle}`,
  );
}
for (const needle of fallback) {
  assert.ok(
    stalePrompt.includes(needle),
    `stale-memory prompt missing OpenAI fallback instruction: ${needle}`,
  );
}

const workerFiles = loadProjectContextFiles({ cwd: workerDir, agentDir });
assert.equal(workerFiles.length, 2, "expected global policy plus worker project context");
const workerPrompt = emit(workerDir, workerFiles);
assert.match(workerPrompt, /FIRSTMATE_WORKER_CONTEXT_MARKER/);
assert.ok(workerPrompt.includes("Do not start another discuss-plan-work cycle"));
assert.ok(workerPrompt.includes("execute the assigned phase only"));
assert.ok(workerPrompt.includes("Workers, scouts, and no-mistakes step agents do not apply this rule"));
assert.ok(workerPrompt.includes("do not start a successor migration"));

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
assert.ok(loaderPrompt.includes("Never omit that look to save quota"));
assert.ok(loaderPrompt.includes("STALE_CAPTAIN_MEMORY_MARKER"));
for (const needle of fallback) {
  assert.ok(
    loaderPrompt.includes(needle),
    `resource-loader prompt missing OpenAI fallback instruction: ${needle}`,
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
