#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
	lstatSync,
	readFileSync,
	readdirSync,
	readlinkSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

const [command, ...arguments_] = process.argv.slice(2);

function fail(message) {
	process.stderr.write(`pi-package-integrity: ${message}\n`);
	process.exit(1);
}

function sortedNames(directory) {
	return readdirSync(directory).sort((left, right) =>
		Buffer.compare(Buffer.from(left), Buffer.from(right)),
	);
}

function treeDigest(root, excludedRootEntries = new Set()) {
	const rootStat = lstatSync(root);
	if (!rootStat.isDirectory()) fail(`tree root is not a directory: ${root}`);
	const hash = createHash("sha256");

	function walk(directory, prefix = "") {
		for (const name of sortedNames(directory)) {
			if (!prefix && excludedRootEntries.has(name)) continue;
			const relativePath = prefix ? `${prefix}/${name}` : name;
			const entryPath = join(directory, name);
			const stat = lstatSync(entryPath);
			if (stat.isDirectory()) {
				walk(entryPath, relativePath);
			} else if (stat.isFile()) {
				hash.update("file\0");
				hash.update(relativePath);
				hash.update("\0");
				hash.update(readFileSync(entryPath));
				hash.update("\0");
			} else if (stat.isSymbolicLink()) {
				hash.update("link\0");
				hash.update(relativePath);
				hash.update("\0");
				hash.update(readlinkSync(entryPath));
				hash.update("\0");
			} else {
				fail(`unsupported tree entry: ${entryPath}`);
			}
		}
	}

	walk(resolve(root));
	return hash.digest("hex");
}

function assertSha256(value, label) {
	if (!/^[0-9a-f]{64}$/.test(value)) fail(`invalid ${label}: ${value}`);
}

function readManifest(path, label) {
	let manifest;
	try {
		manifest = JSON.parse(readFileSync(path, "utf8"));
	} catch {
		fail(`unable to read ${label}: ${path}`);
	}
	if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
		fail(`invalid ${label}: ${path}`);
	}
	return manifest;
}

function dependencyPathParts(name) {
	if (/^@[a-z0-9._~-]+\/[a-z0-9._~-]+$/i.test(name)) return name.split("/");
	if (/^[a-z0-9._~-]+$/i.test(name)) return [name];
	fail(`invalid dependency name: ${name}`);
}

function findDependencyManifest(packageRoot, dependency) {
	const pathParts = dependencyPathParts(dependency);
	let directory = resolve(packageRoot);
	let nodeModulesDirectory = directory;
	while (basename(nodeModulesDirectory) !== "node_modules") {
		const parent = dirname(nodeModulesDirectory);
		if (parent === nodeModulesDirectory) fail(`package is outside node_modules: ${packageRoot}`);
		nodeModulesDirectory = parent;
	}
	const installRoot = dirname(nodeModulesDirectory);
	while (true) {
		const candidate = join(directory, "node_modules", ...pathParts, "package.json");
		try {
			readFileSync(candidate);
			return candidate;
		} catch (error) {
			if (error?.code !== "ENOENT" && error?.code !== "ENOTDIR") {
				fail(`unable to inspect dependency ${dependency}: ${candidate}`);
			}
		}
		if (directory === installRoot) return undefined;
		directory = dirname(directory);
	}
}

function verifyDependencies(packageRoot) {
	const manifestPath = join(resolve(packageRoot), "package.json");
	const manifest = readManifest(manifestPath, "package manifest");
	const dependencies = manifest.dependencies ?? {};
	if (!dependencies || typeof dependencies !== "object" || Array.isArray(dependencies)) {
		fail(`invalid dependencies field: ${manifestPath}`);
	}
	for (const dependency of Object.keys(dependencies)) {
		const dependencyManifestPath = findDependencyManifest(packageRoot, dependency);
		if (!dependencyManifestPath) fail(`missing runtime dependency ${dependency} for ${packageRoot}`);
		const dependencyManifest = readManifest(dependencyManifestPath, `dependency manifest for ${dependency}`);
		if (
			dependencyManifest.name !== dependency ||
			typeof dependencyManifest.version !== "string" ||
			dependencyManifest.version.length === 0
		) {
			fail(`invalid runtime dependency ${dependency} for ${packageRoot}`);
		}
	}
}

if (command === "digest") {
	const [root, ...excludedEntries] = arguments_;
	if (!root) fail("usage: digest <tree-root> [excluded-root-entry ...]");
	process.stdout.write(`${treeDigest(root, new Set(excludedEntries))}\n`);
} else if (command === "verify-tree") {
	const [root, expectedDigest, ...excludedEntries] = arguments_;
	if (!root || !expectedDigest) fail("usage: verify-tree <tree-root> <sha256> [excluded-root-entry ...]");
	assertSha256(expectedDigest, "tree digest");
	if (treeDigest(root, new Set(excludedEntries)) !== expectedDigest) process.exit(1);
} else if (command === "verify-dependencies") {
	const [root] = arguments_;
	if (!root || arguments_.length !== 1) fail("usage: verify-dependencies <package-root>");
	verifyDependencies(root);
} else {
	fail("usage: <digest|verify-tree|verify-dependencies> ...");
}
