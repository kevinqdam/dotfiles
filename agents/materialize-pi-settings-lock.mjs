#!/usr/bin/env node
// Run the narrow Python seeder inside Pi 0.84.3's own global-settings lock.
import { spawn } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [piExecutable, pythonExecutable, materializer, agentDir] = process.argv.slice(2);

function fail(message) {
  console.error(`pi-settings-lock: ${message}`);
  process.exitCode = 1;
}

function packageRoot() {
  if (process.env.PI_TEST_PACKAGE_DIR) {
    return resolve(process.env.PI_TEST_PACKAGE_DIR);
  }
  const piPath = realpathSync(piExecutable);
  const versionRoot = dirname(dirname(piPath));
  return join(
    versionRoot,
    "libexec/lib/node_modules/@earendil-works/pi-coding-agent",
  );
}

function run(command, args, env = process.env) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, { stdio: "inherit", env });
    child.once("error", rejectRun);
    child.once("close", (code, signal) => {
      resolveRun({ code: code ?? 1, signal });
    });
  });
}

async function main() {
  if (!piExecutable || !pythonExecutable || !materializer || !agentDir) {
    fail("usage: <pi-executable> <python-executable> <materializer.py> <agent-dir>");
    return;
  }

  let root;
  try {
    root = packageRoot();
  } catch {
    fail("could not resolve the installed Pi package");
    return;
  }
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  } catch {
    fail("could not read the installed Pi package metadata");
    return;
  }
  if (pkg.name !== "@earendil-works/pi-coding-agent" || pkg.version !== "0.84.3") {
    fail("Pi settings-lock contract requires the audited 0.84.3 package");
    return;
  }

  const settingsManagerUrl = pathToFileURL(
    join(root, "dist/core/settings-manager.js"),
  ).href;
  let FileSettingsStorage;
  try {
    ({ FileSettingsStorage } = await import(settingsManagerUrl));
  } catch {
    fail("Pi 0.84.3 FileSettingsStorage is unavailable");
    return;
  }
  if (typeof FileSettingsStorage !== "function") {
    fail("Pi 0.84.3 FileSettingsStorage API is unsupported");
    return;
  }

  const prepared = await run(pythonExecutable, [materializer, "--prepare", agentDir]);
  if (prepared.code !== 0) {
    process.exitCode = prepared.code;
    return;
  }

  const storage = new FileSettingsStorage(process.cwd(), agentDir);
  let release;
  try {
    // This is the same realpath:false proper-lockfile acquisition used by
    // FileSettingsStorage.withLock for the global settings file.
    release = storage.acquireLockSyncWithRetry(storage.globalSettingsPath);
  } catch (error) {
    fail(`could not acquire Pi's global settings lock: ${error?.code ?? "lock error"}`);
    return;
  }

  try {
    const result = await run(pythonExecutable, [
      materializer,
      "--locked",
      agentDir,
    ]);
    if (result.signal) {
      fail(`settings materializer exited on signal ${result.signal}`);
    } else {
      process.exitCode = result.code;
    }
  } catch (error) {
    fail(`settings materializer could not run: ${error?.message ?? error}`);
  } finally {
    try {
      release();
    } catch (error) {
      fail(`could not release Pi's global settings lock: ${error?.code ?? "lock error"}`);
    }
  }
}

main().catch((error) => {
  fail(`unexpected lock-wrapper failure: ${error?.message ?? error}`);
});
