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

if (command === "digest") {
	const [root, ...excludedEntries] = arguments_;
	if (!root) fail("usage: digest <tree-root> [excluded-root-entry ...]");
	process.stdout.write(`${treeDigest(root, new Set(excludedEntries))}\n`);
} else if (command === "verify-tree") {
	const [root, expectedDigest, ...excludedEntries] = arguments_;
	if (!root || !expectedDigest) fail("usage: verify-tree <tree-root> <sha256> [excluded-root-entry ...]");
	assertSha256(expectedDigest, "tree digest");
	if (treeDigest(root, new Set(excludedEntries)) !== expectedDigest) process.exit(1);
} else {
	fail("usage: <digest|verify-tree> ...");
}
