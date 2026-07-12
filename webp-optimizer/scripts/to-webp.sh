#!/usr/bin/env bash
# to-webp.sh — fallback converter for when Node/sharp isn't available.
# Uses cwebp (libwebp) if present, else ImageMagick's `magick`/`convert`.
#
# Usage: ./to-webp.sh [-q QUALITY] [--delete] <path...>
#   Paths may be image files or directories (directories are scanned
#   non-recursively for .png/.jpg/.jpeg). Originals are KEPT unless --delete.
set -euo pipefail

QUALITY=82
DELETE=0
INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quality) QUALITY="$2"; shift 2 ;;
    --delete) DELETE=1; shift ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "No input paths given." >&2; exit 1
fi

# Pick an available tool.
if command -v cwebp >/dev/null 2>&1; then
  TOOL=cwebp
elif command -v magick >/dev/null 2>&1; then
  TOOL=magick
elif command -v convert >/dev/null 2>&1; then
  TOOL=convert
else
  echo "No converter found. Install libwebp (cwebp) or ImageMagick." >&2
  exit 1
fi

convert_one() {
  local in="$1"
  local out="${in%.*}.webp"
  case "$TOOL" in
    cwebp) cwebp -quiet -q "$QUALITY" "$in" -o "$out" ;;
    magick) magick "$in" -quality "$QUALITY" "$out" ;;
    convert) convert "$in" -quality "$QUALITY" "$out" ;;
  esac
  local before after saved
  before=$(stat -c%s "$in" 2>/dev/null || stat -f%z "$in")
  after=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
  saved=$(( 100 - after * 100 / before ))
  printf '%s (%d KB -> %d KB, -%d%%)\n' "$in" $((before/1000)) $((after/1000)) "$saved"
  [[ $DELETE -eq 1 ]] && rm -f "$in"
}

for p in "${INPUTS[@]}"; do
  if [[ -d "$p" ]]; then
    shopt -s nullglob nocaseglob
    for f in "$p"/*.png "$p"/*.jpg "$p"/*.jpeg; do convert_one "$f"; done
    shopt -u nullglob nocaseglob
  elif [[ -f "$p" ]]; then
    convert_one "$p"
  else
    echo "skip (not found): $p" >&2
  fi
done
