#!/usr/bin/env node
// Compute MAINFRAME's canonical SHA-256 identity for an installed package tree.
// This runtime implementation intentionally uses the same Node.js executable
// required by npm-installed coding-agent wrappers, avoiding a Python dependency
// on stock macOS. Keep its byte stream identical to hash-package-tree.py.

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const DOMAIN = Buffer.from("MAINFRAME-PACKAGE-TREE-SHA256-V1\0", "utf8");

function die(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function utf8Compare(left, right) {
  return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function assertRealDirectory(candidate, message) {
  let metadata;
  try {
    metadata = fs.lstatSync(candidate, { bigint: true });
  } catch {
    die(message);
  }
  if (metadata.isSymbolicLink() || !metadata.isDirectory()) {
    die(message);
  }
}

function normalizeSelections(root, values) {
  const normalized = new Set();
  for (const value of values) {
    const canonical = path.posix.normalize(value);
    const parts = value.split("/");
    if (
      !value ||
      path.posix.isAbsolute(value) ||
      canonical !== value ||
      parts.some((part) => !part || part === "." || part === "..")
    ) {
      die(`selection must be a canonical relative path: ${value}`);
    }
    const selected = path.join(root, ...parts);
    assertRealDirectory(
      selected,
      `selected package tree must be a real directory: ${value}`,
    );
    normalized.add(value);
  }

  return [...normalized]
    .filter(
      (value) =>
        ![...normalized].some(
          (other) => other !== value && value.startsWith(`${other}/`),
        ),
    )
    .sort(utf8Compare);
}

function selectionIncludes(relative, selections) {
  if (selections.length === 0) return true;
  return selections.some(
    (selected) =>
      relative === selected ||
      relative.startsWith(`${selected}/`) ||
      selected.startsWith(`${relative}/`),
  );
}

function main() {
  if (process.argv.length < 3) {
    die(
      "usage: hash-package-tree.mjs PACKAGE_DIRECTORY " +
        "[SELECTED_RELATIVE_DIRECTORY ...]",
    );
  }

  let root = process.argv[2];
  assertRealDirectory(root, `package tree must be a real directory: ${root}`);
  root = fs.realpathSync(root);
  const selections = normalizeSelections(root, process.argv.slice(3));
  const entries = [];

  function visit(current, currentRelative) {
    let names;
    try {
      names = fs.readdirSync(current).sort(utf8Compare);
    } catch (error) {
      die(`could not read package tree directory: ${current}: ${error.message}`);
    }

    for (const name of names) {
      const relative = currentRelative ? `${currentRelative}/${name}` : name;
      if (!selectionIncludes(relative, selections)) continue;
      const entryPath = path.join(current, name);
      let metadata;
      try {
        metadata = fs.lstatSync(entryPath, { bigint: true });
      } catch (error) {
        die(`could not inspect package tree entry: ${relative}: ${error.message}`);
      }
      if (metadata.isSymbolicLink()) {
        die(`package tree contains a symbolic link: ${relative}`);
      }
      if (!metadata.isDirectory() && !metadata.isFile()) {
        die(`package tree contains an unsupported entry: ${relative}`);
      }
      entries.push({ relative, entryPath, metadata });
      if (metadata.isDirectory()) visit(entryPath, relative);
    }
  }

  visit(root, "");
  entries.sort((left, right) => utf8Compare(left.relative, right.relative));

  const digest = crypto.createHash("sha256");
  digest.update(DOMAIN);
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  for (const { relative, entryPath, metadata } of entries) {
    const encodedPath = Buffer.from(relative, "utf8");
    if (encodedPath.includes(0)) die(`package tree path contains NUL: ${relative}`);
    if (metadata.isDirectory()) {
      digest.update(Buffer.from("D\0", "utf8"));
      digest.update(encodedPath);
      digest.update(Buffer.from([0]));
      continue;
    }

    const size = metadata.size;
    digest.update(Buffer.from("F\0", "utf8"));
    digest.update(encodedPath);
    digest.update(Buffer.from([0]));
    digest.update(Buffer.from(`${size}\0`, "ascii"));

    let descriptor;
    let bytesRead = 0n;
    try {
      descriptor = fs.openSync(entryPath, "r");
      while (true) {
        const count = fs.readSync(descriptor, buffer, 0, buffer.length, null);
        if (count === 0) break;
        bytesRead += BigInt(count);
        digest.update(buffer.subarray(0, count));
      }
    } catch (error) {
      die(`could not read package tree file: ${relative}: ${error.message}`);
    } finally {
      if (descriptor !== undefined) fs.closeSync(descriptor);
    }
    if (bytesRead !== size) {
      die(
        "package tree file is dataless, truncated, or changed while hashing: " +
          `${relative} (stat size ${size}, bytes read ${bytesRead})`,
      );
    }
  }

  process.stdout.write(`${digest.digest("hex")}\n`);
}

main();
