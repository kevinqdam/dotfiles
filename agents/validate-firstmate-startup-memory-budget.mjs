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
  const contents = fs.readFileSync(descriptor).toString("latin1");
  const digits = contents.endsWith("\n") ? contents.slice(0, -1) : "";
  const validContents =
    digits.length > 0 &&
    [...digits].every((character) => character >= "0" && character <= "9") &&
    [...digits].some((character) => character !== "0");
  const opened = fs.fstatSync(descriptor, { bigint: true });
  const current = fs.lstatSync(path, { bigint: true });

  if (
    !opened.isFile() ||
    opened.nlink !== 1n ||
    !validContents ||
    !current.isFile() ||
    current.isSymbolicLink() ||
    current.nlink !== 1n ||
    current.dev !== opened.dev ||
    current.ino !== opened.ino
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
