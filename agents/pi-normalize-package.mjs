#!/usr/bin/env node
import { readFile, rename, stat, unlink, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [sdkPath, agentDir, sourceSpec, preserveFirstArgument] = process.argv.slice(2);

if (!sdkPath || !agentDir || !sourceSpec || !["true", "false"].includes(preserveFirstArgument)) {
	process.stderr.write(
		"usage: pi-normalize-package <sdk-path> <agent-directory> <source> <preserve-first-filter>\n",
	);
	process.exit(2);
}

const settingsPath = resolve(agentDir, "settings.json");
const settings = JSON.parse(await readFile(settingsPath, "utf8"));
const { DefaultPackageManager, SettingsManager } = await import(pathToFileURL(sdkPath));
const settingsManager = SettingsManager.inMemory(settings, { projectTrusted: false });
const packageManager = new DefaultPackageManager({ cwd: agentDir, agentDir, settingsManager });
const reviewedIdentity = packageManager.getPackageIdentity(sourceSpec, "user");
const packages = Array.isArray(settings.packages) ? settings.packages : [];
const sourceOf = (entry) => (typeof entry === "string" ? entry : entry?.source);
const matchesIdentity = (entry) =>
	typeof sourceOf(entry) === "string" &&
	packageManager.getPackageIdentity(sourceOf(entry), "user") === reviewedIdentity;
const firstMatchingEntry = packages.find(matchesIdentity);
const preserveFirst =
	preserveFirstArgument === "true" && sourceOf(firstMatchingEntry) === sourceSpec;
const replacement = preserveFirst ? firstMatchingEntry : sourceSpec;
const normalizedPackages = [];
let inserted = false;
for (const entry of packages) {
	if (!matchesIdentity(entry)) {
		normalizedPackages.push(entry);
		continue;
	}
	if (!inserted) {
		normalizedPackages.push(replacement);
		inserted = true;
	}
}
if (!inserted) normalizedPackages.push(replacement);
settings.packages = normalizedPackages;

const settingsStat = await stat(settingsPath);
const temporaryPath = `${settingsPath}.tmp.${process.pid}`;
try {
	await writeFile(temporaryPath, `${JSON.stringify(settings, null, 2)}\n`, { mode: settingsStat.mode });
	await rename(temporaryPath, settingsPath);
} catch (error) {
	await unlink(temporaryPath).catch(() => {});
	throw error;
}
