#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
	lstatSync,
	readFileSync,
	readdirSync,
	readlinkSync,
} from "node:fs";
import { join, resolve } from "node:path";

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

function loadContract(contractPath) {
	const contract = JSON.parse(readFileSync(contractPath, "utf8"));
	if (contract.schemaVersion !== 1) fail(`unsupported contract schema: ${contract.schemaVersion}`);
	return contract;
}

function installedDependencyNames(nodeModulesPath) {
	const names = [];
	for (const name of sortedNames(nodeModulesPath)) {
		if (name === ".package-lock.json") continue;
		const entryPath = join(nodeModulesPath, name);
		const stat = lstatSync(entryPath);
		if (!stat.isDirectory()) fail(`unexpected dependency-graph entry: ${entryPath}`);
		if (name.startsWith("@")) {
			for (const scopedName of sortedNames(entryPath)) {
				const scopedPath = join(entryPath, scopedName);
				if (!lstatSync(scopedPath).isDirectory()) fail(`unexpected scoped dependency entry: ${scopedPath}`);
				names.push(`${name}/${scopedName}`);
			}
		} else {
			names.push(name);
		}
	}
	return names;
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
} else if (command === "verify-dependency-graph") {
	const [packageRoot, contractPath, sourceSpec] = arguments_;
	if (!packageRoot || !contractPath || !sourceSpec) {
		fail("usage: verify-dependency-graph <package-root> <contract> <source>");
	}
	const contract = loadContract(contractPath);
	const dependencies = contract.gitPackages?.[sourceSpec]?.runtimeDependencies;
	if (!Array.isArray(dependencies) || dependencies.length === 0) fail(`missing dependency contract: ${sourceSpec}`);
	const nodeModulesPath = join(packageRoot, "node_modules");
	const installedNames = installedDependencyNames(nodeModulesPath);
	const expectedNames = dependencies.map(({ name }) => name).sort();
	if (JSON.stringify(installedNames) !== JSON.stringify(expectedNames)) process.exit(1);
	for (const dependency of dependencies) {
		const { name, version, treeSha256 } = dependency;
		if (!name || !version || !treeSha256) fail(`invalid dependency contract: ${sourceSpec}`);
		assertSha256(treeSha256, `${name} tree digest`);
		const dependencyRoot = join(nodeModulesPath, ...name.split("/"));
		const manifest = JSON.parse(readFileSync(join(dependencyRoot, "package.json"), "utf8"));
		if (manifest.name !== name || manifest.version !== version) process.exit(1);
		if (treeDigest(dependencyRoot, new Set(["node_modules"])) !== treeSha256) process.exit(1);
	}
} else {
	fail("usage: <digest|verify-tree|verify-dependency-graph> ...");
}
