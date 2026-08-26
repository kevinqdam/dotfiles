import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const [sdkPath, agentDir, sourceSpec, extensionPath] = process.argv.slice(2);

if (!sdkPath || !agentDir || !sourceSpec || !extensionPath) {
	process.stderr.write("usage: pi-effective-package-state <sdk-path> <agent-directory> <source> <extension-path>\n");
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
const reviewedIdentity = packageManager.getPackageIdentity(sourceSpec, "user");
const identityConfigured = packageManager
	.listConfiguredPackages()
	.some(
		(entry) =>
			entry.scope === "user" && packageManager.getPackageIdentity(entry.source, "user") === reviewedIdentity,
	);
const resources = await packageManager.resolve(async () => "skip");
const expectedPath = resolve(extensionPath);
const extension = resources.extensions.find(
	(entry) =>
		resolve(entry.path) === expectedPath &&
		entry.metadata.origin === "package" &&
		entry.metadata.scope === "user",
);

process.stdout.write(
	JSON.stringify({
		identityConfigured,
		sourceMatches: extension?.metadata.source === sourceSpec,
		extensionEnabled: extension?.enabled === true,
	}),
);
