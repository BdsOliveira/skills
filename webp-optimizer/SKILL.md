---
name: webp-optimizer
description: >-
  Convert one or many images (.png/.jpg/.jpeg/.tiff) to WebP (or AVIF) to shrink
  page weight and speed up websites, typically cutting file size 70–98% with no
  visible quality loss. Use this whenever the user hands over image paths or an
  image folder and wants them optimized, compressed, made web-ready, or "smaller
  for the site" — even if they don't say the word "WebP." Also use when a user
  mentions slow-loading images, large photo assets in a web/app project (e.g.
  public/, assets/, static/), Lighthouse/PageSpeed image warnings, or wants to
  batch-convert screenshots or client photos before shipping. Handles a single
  file, a list of files, or a whole directory.
---

# WebP optimizer

Convert raster images to WebP so websites download far fewer kilobytes. WebP
holds the same visual quality as PNG/JPEG at roughly **70–98% less weight**,
which is usually the single biggest, cheapest page-speed win available.

The core job is small: take the image path(s) the user gives you, produce
`.webp` siblings, and confirm the savings actually landed. Everything below is
about doing that reliably across different machines and then cleaning up after.

## Workflow

### 1. Gather the inputs

The user may give a single path, a list, or a folder. You don't need to expand
folders yourself — the converter script scans directories for you. Just collect
what they pointed at. If they're vague ("optimize the client photos"), find the
likely folder (`public/`, `assets/`, `static/`, `images/`) and confirm before
running.

### 2. Convert

Two paths depending on the environment. Prefer **sharp** — it's fast, gives the
most control, and produces the best-compressed output. Fall back to CLI tools
only if Node isn't available.

**Path A — sharp (preferred).** `sharp` is a temporary build tool here, not a
project dependency, so install it with `--no-save` (writes to `node_modules/`
but leaves `package.json` and the lockfile untouched) and remove it after:

```bash
npm install --no-save sharp
node <skill>/scripts/to-webp.mjs <path...> --quality 82
npm remove --no-save sharp
```

`scripts/to-webp.mjs` accepts any mix of files and directories and these flags:

| Flag | Default | Purpose |
| --- | --- | --- |
| `--quality N` / `-q` | 82 | 0–100. 80–85 is the sweet spot. |
| `--resize W` / `-r` | off | Cap width to W px, keep aspect, never upscale. |
| `--recursive` | off | Descend into subdirectories. |
| `--avif` | off | Emit `.avif` instead (smaller still, slightly slower). |
| `--delete` | off | Delete each original after a successful convert. |

Originals are **kept by default** — don't pass `--delete` unless the user asks,
since the source may not be recoverable if it isn't in git.

**Path B — CLI fallback (no Node).** Use the bundled `scripts/to-webp.sh`, which
auto-detects `cwebp` (libwebp) or ImageMagick:

```bash
<skill>/scripts/to-webp.sh -q 82 <path...>
```

If neither tool is installed, offer to install one (`sudo apt install webp` for
`cwebp` on Ubuntu/WSL, or `brew install webp` on macOS) rather than silently
failing.

### 3. Report the savings

Both scripts print a per-file line and a total, e.g.
`Nadja.png 0.44MB -> Nadja.webp 106KB (-76%)`. Read this back to the user — the
whole point is the size reduction, so make it visible. If a file barely shrank
(under ~20%) or grew, it's likely already compressed or a photo where a lower
quality is fine; mention it rather than hiding it.

### 4. Offer to update code references (opt-in)

If these images are referenced in a codebase, the old `.png`/`.jpg` paths now
point at files that may still exist alongside the new `.webp` — or will 404 if
originals were deleted. Offer to rewrite the references; don't do it unasked,
because a blind find-and-replace can hit unrelated strings.

When the user says yes:

1. Find real references first so you know the blast radius:
   ```bash
   grep -rn -e '\.png' -e '\.jpg' -e '\.jpeg' src/ public/ 2>/dev/null
   ```
2. Rewrite only the files that reference the converted images, and only the
   matching filenames — prefer targeted edits over a repo-wide `sed`. If the set
   is large and unambiguous, a scoped `sed -i 's/\.png"/.webp"/g' <file>` is
   fine.
3. Re-grep to confirm nothing broken is left behind, and if the project builds
   (`npm run build`), run it so a wrong path surfaces immediately.

### 5. Clean up

If you used sharp, remove it and confirm the manifest is untouched:

```bash
npm remove --no-save sharp
git status --short package.json package-lock.json   # empty = clean
```

## Choosing quality

`--quality` is the main dial. Sensible defaults:

| Quality | When |
| --- | --- |
| 90–100 | Rare — only when no detail can be lost. |
| **80–85** | Default. Best weight-vs-quality balance for photos and hero images. |
| 65–75 | Thumbnails, small images, backgrounds. |
| < 60 | Only when weight is critical and quality barely matters. |

The biggest wins come from **resizing oversized images**: a 4000px photo
displayed at 800px is mostly wasted bytes. If the user mentions display size or
you can tell an asset is far larger than needed, suggest `--resize`.

## AVIF

For even smaller files, `--avif` (quality ~55 is a good start) compresses harder
than WebP. It's slightly slower to encode and has marginally lower (but now very
broad) browser support. WebP is the safer default; reach for AVIF when the user
explicitly wants maximum compression and modern-browser-only is acceptable.
