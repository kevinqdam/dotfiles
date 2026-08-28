#!/usr/bin/env node
import { pathToFileURL } from "node:url";

const [sdkPath, agentDir, sourceSpec, preserveFirstArgument] = process.argv.slice(2);

if (!sdkPath || !agentDir || !sourceSpec || !["true", "false"].includes(preserveFirstArgument)) {
	process.stderr.write(
		"usage: pi-normalize-package <sdk-path> <agent-directory> <source> <preserve-first-filter>\n",
	);
	process.exit(2);
}

const { DefaultPackageManager, SettingsManager } = await import(pathToFileURL(sdkPath));
const settingsManager = SettingsManager.create(agentDir, agentDir, { projectTrusted: false });
const loadErrors = settingsManager.drainErrors();
if (loadErrors.length > 0) throw loadErrors[0].error;
const packageManager = new DefaultPackageManager({ cwd: agentDir, agentDir, settingsManager });
const reviewedIdentity = packageManager.getPackageIdentity(sourceSpec, "user");
const packages = settingsManager.getPackages();
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
settingsManager.setPackages(normalizedPackages);
await settingsManager.flush();
const saveErrors = settingsManager.drainErrors();
if (saveErrors.length > 0) throw saveErrors[0].error;
