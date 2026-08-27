import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [sdkPath, agentDir, sourceSpec, ...resourceArguments] = process.argv.slice(2);

if (!sdkPath || !agentDir || !sourceSpec || resourceArguments.length === 0 || resourceArguments.length % 2 !== 0) {
	process.stderr.write(
		"usage: pi-effective-package-state <sdk-path> <agent-directory> <source> <resource-type> <resource-path> [...]\n",
	);
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
const configuredEntries = packageManager
	.listConfiguredPackages()
	.filter(
		(entry) =>
			entry.scope === "user" && packageManager.getPackageIdentity(entry.source, "user") === reviewedIdentity,
	);
const identityConfigured = configuredEntries.length > 0;
const firstConfiguredSourceReviewed = configuredEntries[0]?.source === sourceSpec;
const allConfiguredSourcesReviewed =
	identityConfigured && configuredEntries.every((entry) => entry.source === sourceSpec);
const resources = await packageManager.resolve(async () => "skip");
const requiredResources = [];
for (let index = 0; index < resourceArguments.length; index += 2) {
	const resourceType = resourceArguments[index];
	const resourcePath = resourceArguments[index + 1];
	if (!Object.hasOwn(resources, resourceType)) throw new Error(`unknown Pi resource type: ${resourceType}`);
	requiredResources.push({ resourceType, resourcePath: resolve(resourcePath) });
}
const requiredResourcesEnabled = requiredResources.every(({ resourceType, resourcePath }) =>
	resources[resourceType].some(
		(entry) =>
			resolve(entry.path) === resourcePath &&
			entry.enabled === true &&
			entry.metadata.source === sourceSpec &&
			entry.metadata.origin === "package" &&
			entry.metadata.scope === "user",
	),
);

process.stdout.write(
	JSON.stringify({
		identityConfigured,
		firstConfiguredSourceReviewed,
		allConfiguredSourcesReviewed,
		requiredResourcesEnabled,
	}),
);
