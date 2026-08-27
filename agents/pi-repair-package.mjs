#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [sdkPath, agentDir, sourceSpec] = process.argv.slice(2);

if (!sdkPath || !agentDir || !sourceSpec) {
	process.stderr.write("usage: pi-repair-package <sdk-path> <agent-directory> <source>\n");
	process.exit(2);
}

let settings = {};
try {
	settings = JSON.parse(await readFile(resolve(agentDir, "settings.json"), "utf8"));
} catch (error) {
	if (error?.code !== "ENOENT") throw error;
}

const { DefaultPackageManager, SettingsManager } = await import(pathToFileURL(sdkPath));
const settingsManager = SettingsManager.inMemory(settings, { projectTrusted: false });
const packageManager = new DefaultPackageManager({ cwd: agentDir, agentDir, settingsManager });
await packageManager.remove(sourceSpec, { local: false });
await packageManager.install(sourceSpec, { local: false });
