#!/usr/bin/env node
import fs from "node:fs";

const [path] = process.argv.slice(2);

if (!path) {
  process.exit(2);
}

let descriptor;
try {
  descriptor = fs.openSync(
    path,
    fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
  );
  const before = fs.fstatSync(descriptor, { bigint: true });
  const contents = fs.readFileSync(descriptor).toString("latin1");
  const digits = contents.endsWith("\n") ? contents.slice(0, -1) : "";
  const validContents =
    digits.length > 0 &&
    digits[0] >= "1" &&
    digits[0] <= "9" &&
    [...digits.slice(1)].every(
      (character) => character >= "0" && character <= "9",
    );
  const after = fs.fstatSync(descriptor, { bigint: true });
  const current = fs.lstatSync(path, { bigint: true });
  const metadataMatches = (left, right) =>
    left.dev === right.dev &&
    left.ino === right.ino &&
    left.size === right.size &&
    left.ctimeNs === right.ctimeNs &&
    left.mtimeNs === right.mtimeNs;

  if (
    !before.isFile() ||
    before.nlink !== 1n ||
    !after.isFile() ||
    after.nlink !== 1n ||
    !validContents ||
    !metadataMatches(before, after) ||
    !current.isFile() ||
    current.isSymbolicLink() ||
    current.nlink !== 1n ||
    !metadataMatches(after, current)
  ) {
    process.exitCode = 1;
  }
} catch {
  process.exitCode = 1;
} finally {
  if (descriptor !== undefined) {
    fs.closeSync(descriptor);
  }
}
