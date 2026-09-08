#!/usr/bin/env bash
# Behavioral contract for Firstmate coordinator policy delivery through Pi
# context loading. Asserts emitted instructions, not source grep of the
# policy file as the sole proof. Instruction presence is not model obedience.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POLICY="$SCRIPT_DIR/agents/pi/AGENTS.md"
HOME_NIX="$SCRIPT_DIR/home.nix"
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
project="$TMP/firstmate"
mkdir -p "$agent_dir" "$project"
cp "$POLICY" "$agent_dir/AGENTS.md"
cat > "$project/AGENTS.md" <<'EOF'
# Firstmate

FIRSTMATE_PROJECT_CONTEXT_MARKER

You are the first mate.
EOF

node --input-type=module - "$PI_PKG" "$agent_dir" "$project" "$POLICY" <<'EOF'
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const piPkg = process.argv[2];
const agentDir = resolve(process.argv[3]);
const projectDir = resolve(process.argv[4]);
const policyPath = resolve(process.argv[5]);
const policy = readFileSync(policyPath, "utf8");

const { loadProjectContextFiles, DefaultResourceLoader } = await import(
  pathToFileURL(join(piPkg, "dist/index.js")).href
);
const { buildSystemPrompt } = await import(
  pathToFileURL(join(piPkg, "dist/core/system-prompt.js")).href
);

const contextFiles = loadProjectContextFiles({
  cwd: projectDir,
  agentDir,
});
assert.equal(contextFiles.length, 2, "expected global policy plus Firstmate project context");
assert.equal(contextFiles[0].path, join(agentDir, "AGENTS.md"));
assert.equal(contextFiles[0].content, policy);
assert.equal(contextFiles[1].path, join(projectDir, "AGENTS.md"));
assert.match(contextFiles[1].content, /FIRSTMATE_PROJECT_CONTEXT_MARKER/);

const prompt = buildSystemPrompt({
  cwd: projectDir,
  contextFiles,
  selectedTools: ["read", "bash", "edit", "write"],
  toolSnippets: {
    read: "Read file contents",
    bash: "Execute bash commands",
    edit: "Edit files",
    write: "Write files",
  },
});

assert.match(prompt, /<project_context>/);
assert.match(
  prompt,
  new RegExp(`<project_instructions path="${contextFiles[0].path.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&")}">`),
);
assert.match(prompt, /FIRSTMATE_PROJECT_CONTEXT_MARKER/);

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
  "Astra high owns the written plan artifact",
  "Wait for go before `gsd-work` unless the captain already authorized implementation of that same outcome",
  "Record the actual authorization",
  "Plan-only remains plan-only",
  "Grok implements, tests, lints, and drives no-mistakes/CI",
  "one bounded Astra-high review of finished output",
  "Never omit that look to save quota",
  "skip no-mistakes's `review` step, not validation",
  "Pi+Grok",
  "No automatic second Astra loop",
  "not implicit merge permission",
  "execute the assigned phase only",
  "stage names, not shell commands",
  "--no-context-files",
  "AGENTS.override.md",
];
for (const needle of required) {
  assert.ok(prompt.includes(needle), `emitted prompt missing: ${needle}`);
}

// Four coordinator cases: instruction presence only. These do not prove
// that a model will obey the policy.
assert.ok(
  prompt.includes("An ambiguous feature still starts `gsd-discuss` without asking"),
  "ambiguous-feature instructions missing from emitted prompt",
);
assert.ok(
  prompt.includes("unless the captain already authorized implementation of that same outcome"),
  "already-authorized instructions missing from emitted prompt",
);
assert.ok(
  prompt.includes("Plan-only remains plan-only"),
  "plan-only instructions missing from emitted prompt",
);
assert.ok(
  prompt.includes("Do not start another discuss-plan-work cycle"),
  "nonrecursive-worker instructions missing from emitted prompt",
);

const disabledLoader = new DefaultResourceLoader({
  cwd: projectDir,
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
  cwd: projectDir,
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
assert.match(loaded[1].content, /FIRSTMATE_PROJECT_CONTEXT_MARKER/);
const loaderPrompt = buildSystemPrompt({
  cwd: projectDir,
  contextFiles: loaded,
});
assert.ok(loaderPrompt.includes("Never omit that look to save quota"));
assert.ok(loaderPrompt.includes("FIRSTMATE_PROJECT_CONTEXT_MARKER"));

const overrideDir = mkdtempSync(join(tmpdir(), "firstmate-policy-override-"));
writeFileSync(join(overrideDir, "AGENTS.md"), policy);
writeFileSync(
  join(overrideDir, "AGENTS.override.md"),
  "OVERRIDE_CONTEXT_MARKER\nThis override replaces AGENTS.md in this directory.\n",
);
const overrideFiles = loadProjectContextFiles({
  cwd: projectDir,
  agentDir: overrideDir,
});
assert.equal(overrideFiles[0].path, join(overrideDir, "AGENTS.override.md"));
assert.match(overrideFiles[0].content, /OVERRIDE_CONTEXT_MARKER/);
assert.ok(!overrideFiles[0].content.includes("gsd-discuss"));
assert.ok(
  overrideFiles.some((file) => file.path === join(projectDir, "AGENTS.md")),
  "override of global context must not drop Firstmate project context",
);

const customAgentDir = mkdtempSync(join(tmpdir(), "firstmate-policy-custom-agent-"));
mkdirSync(customAgentDir, { recursive: true });
const customFiles = loadProjectContextFiles({
  cwd: projectDir,
  agentDir: customAgentDir,
});
assert.ok(
  !customFiles.some((file) => file.content === policy),
  "custom Pi agent directories without this file must not claim policy delivery",
);
assert.ok(customFiles.some((file) => file.path === join(projectDir, "AGENTS.md")));
EOF

# Development-only live model checks are not this suite. Instruction presence
# for ambiguous feature, already-authorized outcome, plan-only, and
# nonrecursive worker behavior is asserted above and does not prove obedience.
if [ "${FIRSTMATE_POLICY_MODEL_CHECKS:-}" = 1 ]; then
  printf 'firstmate-policy.test.sh: live model checks are development-only and are not run as deterministic tests\n'
fi

printf 'ok - Pi context loader emits Firstmate coordinator policy with isolated global and project context\n'
