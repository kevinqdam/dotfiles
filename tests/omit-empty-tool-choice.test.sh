#!/usr/bin/env bash
# Behavioral contract for dropping empty tool_choice on Pi provider requests.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXTENSION="$REPO_ROOT/agents/pi/extensions/omit-empty-tool-choice.ts"
HOME_NIX="$REPO_ROOT/home.nix"

fail() {
  printf 'omit-empty-tool-choice.test.sh: %s\n' "$*" >&2
  exit 1
}

grep -Fqx '  home.file.".pi/agent/extensions/firstmate-bootstrap.ts".source = ./agents/pi/extensions/firstmate-bootstrap.ts;' \
  "$HOME_NIX" || fail 'home.nix no longer sources firstmate-bootstrap.ts'
grep -Fqx '  home.file.".pi/agent/extensions/omit-empty-tool-choice.ts".source = ./agents/pi/extensions/omit-empty-tool-choice.ts;' \
  "$HOME_NIX" || fail 'home.nix does not source omit-empty-tool-choice.ts'

node --input-type=module - "$EXTENSION" <<'EOF'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const extension = (await import(pathToFileURL(extensionPath).href)).default;

let handler;
const pi = {
  on(name, fn) {
    assert.equal(name, "before_provider_request");
    handler = fn;
  },
};

extension(pi);
assert.equal(typeof handler, "function");

assert.deepEqual(
  handler({ payload: { model: "grok", tool_choice: "none" } }),
  { model: "grok" },
);
assert.deepEqual(
  handler({ payload: { model: "grok", tool_choice: "none", tools: [] } }),
  { model: "grok", tools: [] },
);

const withTools = {
  model: "grok",
  tool_choice: "none",
  tools: [{ type: "function", name: "web_search" }],
};
assert.equal(handler({ payload: withTools }), undefined);
assert.deepEqual(withTools, {
  model: "grok",
  tool_choice: "none",
  tools: [{ type: "function", name: "web_search" }],
});

assert.equal(handler({ payload: { model: "grok" } }), undefined);
assert.equal(handler({ payload: { model: "grok", tools: [] } }), undefined);

EOF

printf 'ok - omit-empty-tool-choice strips empty tool_choice and is sourced from home.nix\n'
