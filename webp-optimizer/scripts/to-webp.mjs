// to-webp.mjs — convert images to WebP (or AVIF) with sharp.
//
// Usage:
//   node to-webp.mjs <path...> [--quality N] [--resize W] [--avif] [--delete]
//
// Accepts any mix of individual image paths and directories. Directories are
// scanned (non-recursively by default; pass --recursive to descend). Only
// .png/.jpg/.jpeg/.tiff inputs are converted; anything else is skipped so you
// can safely point it at a whole folder. Originals are KEPT unless --delete.
//
// Prints one line per image with the size saved, then a total. The output is
// meant to be read back by the caller to confirm the ~70%+ savings landed.

import { statSync, unlinkSync, readdirSync } from "fs";
import { join, parse } from "path";
import { createRequire } from "module";
import { pathToFileURL } from "url";

// This script lives inside the skill directory, but `sharp` is installed in the
// *target project's* node_modules (via `npm install --no-save sharp` run there).
// Node's ESM loader resolves bare imports relative to this file, so a plain
// `import "sharp"` would miss it. Resolve from the project's cwd instead.
let sharp;
try {
  const requireFromCwd = createRequire(join(process.cwd(), "noop.js"));
  sharp = (await import(pathToFileURL(requireFromCwd.resolve("sharp")))).default;
} catch {
  try {
    sharp = (await import("sharp")).default; // fall back to normal resolution
  } catch {
    console.error(
      "Could not load 'sharp'. Install it in this project first:\n" +
        "  npm install --no-save sharp\n" +
        "and run this script from the project root, or use scripts/to-webp.sh (cwebp/ImageMagick)."
    );
    process.exit(1);
  }
}

const IMAGE_EXTS = [".png", ".jpg", ".jpeg", ".tiff", ".tif"];

// --- tiny arg parser (no deps) ---
const args = process.argv.slice(2);
const opts = { quality: 82, resize: null, avif: false, delete: false, recursive: false };
const inputs = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--quality" || a === "-q") opts.quality = Number(args[++i]);
  else if (a === "--resize" || a === "-r") opts.resize = Number(args[++i]);
  else if (a === "--avif") opts.avif = true;
  else if (a === "--delete") opts.delete = true;
  else if (a === "--recursive") opts.recursive = true;
  else inputs.push(a);
}

if (inputs.length === 0) {
  console.error("No input paths given. Pass image files or directories.");
  process.exit(1);
}

// Expand directories into their image files.
function collect(path) {
  let s;
  try {
    s = statSync(path);
  } catch {
    console.error(`skip (not found): ${path}`);
    return [];
  }
  if (s.isDirectory()) {
    const out = [];
    for (const entry of readdirSync(path)) {
      const full = join(path, entry);
      if (statSync(full).isDirectory()) {
        if (opts.recursive) out.push(...collect(full));
      } else if (IMAGE_EXTS.includes(parse(entry).ext.toLowerCase())) {
        out.push(full);
      }
    }
    return out;
  }
  // A file given explicitly is converted even if its extension is unusual,
  // as long as it looks like a raster image we support.
  if (IMAGE_EXTS.includes(parse(path).ext.toLowerCase())) return [path];
  console.error(`skip (unsupported type): ${path}`);
  return [];
}

const files = [...new Set(inputs.flatMap(collect))];
if (files.length === 0) {
  console.error("No convertible images found.");
  process.exit(1);
}

// Format a size-change percentage: "-76%" for shrink, "+38% LARGER" for growth
// (growth means the source was already better-compressed than WebP at this quality).
const pct = (saved) =>
  saved >= 0 ? `-${saved.toFixed(0)}%` : `+${(-saved).toFixed(0)}% LARGER`;

const fmt = opts.avif ? "avif" : "webp";
let totalBefore = 0;
let totalAfter = 0;
let failures = 0;

for (const inPath of files) {
  const { dir, name } = parse(inPath);
  const outPath = join(dir, `${name}.${fmt}`);
  try {
    let pipe = sharp(inPath);
    if (opts.resize) pipe = pipe.resize({ width: opts.resize, withoutEnlargement: true });
    pipe = opts.avif ? pipe.avif({ quality: opts.quality }) : pipe.webp({ quality: opts.quality });
    await pipe.toFile(outPath);

    const before = statSync(inPath).size;
    const after = statSync(outPath).size;
    totalBefore += before;
    totalAfter += after;
    const saved = 100 - (after / before) * 100;
    console.log(
      `${inPath} ${(before / 1e6).toFixed(2)}MB -> ${name}.${fmt} ${(after / 1e3).toFixed(0)}KB (${pct(saved)})`
    );
    if (opts.delete) unlinkSync(inPath);
  } catch (err) {
    failures++;
    console.error(`FAILED ${inPath}: ${err.message}`);
  }
}

if (totalBefore > 0) {
  const savedTotal = 100 - (totalAfter / totalBefore) * 100;
  console.log(
    `\nTOTAL: ${(totalBefore / 1e6).toFixed(2)}MB -> ${(totalAfter / 1e6).toFixed(2)}MB (${pct(savedTotal)}) across ${files.length - failures} image(s)`
  );
}
if (failures > 0) process.exit(2);
