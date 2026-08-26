#!/usr/bin/env bash
# Behavioral contract for Pi's documented external-editor environment fallback.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'pi-editor.test.sh: %s\n' "$*" >&2
  exit 1
}

session_variables=$(nix eval --impure --json \
  '.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.sessionVariables')
jq -e '.VISUAL == "vim" and .EDITOR == "vim"' <<<"$session_variables" >/dev/null \
  || fail 'Home Manager did not export Vim as VISUAL and EDITOR'

VISUAL=vim EDITOR=emacs node --input-type=module <<'EOF'
import assert from "node:assert/strict";
import { SettingsManager } from "/opt/homebrew/Cellar/pi-coding-agent/0.84.3/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/core/settings-manager.js";

const environmentFallback = SettingsManager.inMemory({});
assert.equal(environmentFallback.getExternalEditorCommand(), "vim");

const explicitPiSetting = SettingsManager.inMemory({ externalEditor: "nano" });
assert.equal(explicitPiSetting.getExternalEditorCommand(), "nano");
EOF

printf 'ok - Home Manager exports Vim and Pi resolves it through the documented external-editor precedence\n'
