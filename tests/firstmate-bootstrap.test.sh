#!/usr/bin/env bash
# Behavioral contract for canonical Firstmate home defaults and explicit overrides.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXTENSION="$REPO_ROOT/agents/pi/extensions/firstmate-bootstrap.ts"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-bootstrap-test.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

primary_root="$TMP/primary"
canonical_home="$TMP/canonical-home"
project="$TMP/project"
secondmate_root="$TMP/secondmate"
secondmate_home="$TMP/secondmate-home"
mkdir -p "$primary_root" "$project" "$secondmate_root"

(
  cd "$primary_root"
  env -u FM_HOME -u FM_ROOT_OVERRIDE -u FM_FIRSTMATE_ACTIVE \
    FIRSTMATE_ROOT="$primary_root" \
    FIRSTMATE_HOME="$canonical_home" \
    node --input-type=module - "$EXTENSION" "$primary_root" "$canonical_home" <<'EOF'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const primaryRoot = process.argv[3];
const canonicalHome = process.argv[4];
await import(pathToFileURL(extensionPath).href);
assert.equal(process.env.FM_ROOT_OVERRIDE, primaryRoot);
assert.equal(process.env.FM_HOME, canonicalHome);
EOF
)

(
  cd "$project"
  env -u FM_HOME -u FM_ROOT_OVERRIDE -u FM_FIRSTMATE_ACTIVE \
    FIRSTMATE_ROOT="$primary_root" \
    FIRSTMATE_HOME="$canonical_home" \
    node --input-type=module - "$EXTENSION" "$primary_root" "$canonical_home" <<'EOF'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const primaryRoot = process.argv[3];
const canonicalHome = process.argv[4];
const extension = (await import(pathToFileURL(extensionPath).href)).default;

let command;
let reloaded = false;
const notifications = [];
const pi = {
  registerCommand(_name, definition) {
    command = definition;
  },
  async exec(executable, args) {
    assert.equal(executable, "git");
    assert.deepEqual(args, ["-C", process.cwd(), "rev-parse", "--show-toplevel"]);
    return { code: 0 };
  },
  on() {},
};
await extension(pi);
assert.equal(process.env.FM_HOME, undefined);
assert.ok(command);
await command.handler("", {
  reload: async () => {
    reloaded = true;
  },
  ui: {
    notify(message, level) {
      notifications.push({ message, level });
    },
  },
});
assert.equal(process.env.FM_FIRSTMATE_ACTIVE, "1");
assert.equal(process.env.FM_ROOT_OVERRIDE, primaryRoot);
assert.equal(process.env.FM_HOME, canonicalHome);
assert.equal(reloaded, true);
assert.deepEqual(notifications, [
  {
    message: `Activating Firstmate for ${process.cwd()}; reloading Pi...`,
    level: "info",
  },
]);
EOF
)

(
  cd "$secondmate_root"
  FM_FIRSTMATE_ACTIVE=1 \
    FM_ROOT_OVERRIDE='' \
    FM_HOME="$secondmate_home" \
    FIRSTMATE_ROOT="$primary_root" \
    FIRSTMATE_HOME="$canonical_home" \
    node --input-type=module - "$EXTENSION" "$secondmate_root" "$secondmate_home" <<'EOF'
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const secondmateRoot = process.argv[3];
const secondmateHome = process.argv[4];
const extension = (await import(pathToFileURL(extensionPath).href)).default;

const events = new Map();
const pi = {
  registerCommand() {},
  on(name, handler) {
    events.set(name, handler);
  },
};
await extension(pi);
assert.equal(process.env.FM_ROOT_OVERRIDE, "");
assert.equal(process.env.FM_HOME, secondmateHome);
const resources = await events.get("resources_discover")();
assert.deepEqual(resources, {
  skillPaths: [resolve(secondmateRoot, ".agents/skills")],
});
const notifications = [];
events.get("session_start")({}, {
  ui: {
    notify(message, level) {
      notifications.push({ message, level });
    },
  },
});
assert.deepEqual(notifications, [
  { message: `Firstmate active: ${secondmateHome}`, level: "info" },
]);
EOF
)

printf 'ok - Pi bootstrap canonical home, activation, and secondmate override contracts\n'
