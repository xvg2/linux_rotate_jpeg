#!/usr/bin/env bash
set -euo pipefail

# Usage: ./optimize-jpeg.sh /path/to/src /path/to/dest [rotation]
SRC="${1:-}" 
DST="${2:-}"
ROT="${3:-0}"  # rotation in degrees: 0,90,180,270

if [[ -z "$SRC" || -z "$DST" ]]; then
  echo "Usage: $0 /path/to/source /path/to/dest [rotation]" >&2
  exit 2
fi

# Validate rotation
case "$ROT" in
  0|90|180|270) ;;
  *)
    echo "Rotation must be one of: 0, 90, 180, 270" >&2
    exit 2
    ;;
esac

# Ensure absolute-ish paths
SRC="$(readlink -f "$SRC")"
DST="$(readlink -f "$DST")"

# Create dest root if needed
mkdir -p "$DST"

# Find JPEGs (case-insensitive) and process
find "$SRC" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 |
while IFS= read -r -d '' srcfile; do
  rel="${srcfile#$SRC/}"
  destfile="$DST/$rel"
  destdir="$(dirname "$destfile")"
  mkdir -p "$destdir"

  tmp="$(mktemp "${destdir}/.jpegopt.XXXXXX")" || exit 1

  # Build jpegtran args: preserve metadata with -copy all, optimize; add -rotate if requested
  jargs=( -copy all -optimize -perfect -outfile "$tmp" )
  if [[ "$ROT" != "0" ]]; then
    jargs+=( -rotate "$ROT" )
  fi
  jargs+=( "$srcfile" )

  if jpegtran "${jargs[@]}" >/dev/null 2>&1; then
    :
  else
    rm -f "$tmp"
    cp -p -- "$srcfile" "$destfile"
    echo "Copied (jpegtran failed): $rel"
    continue
  fi

  orig_size=$(stat -c%s -- "$srcfile")
  opt_size=$(stat -c%s -- "$tmp")

  if (( opt_size < orig_size )); then
    mv -f -- "$tmp" "$destfile"
    echo "Optimized: $rel  ($orig_size -> $opt_size bytes)"
  else
    rm -f "$tmp"
    cp -p -- "$srcfile" "$destfile"
    echo "Kept original (no savings): $rel"
  fi

  # Preserve ownership and permissions where possible
  chown --reference="$srcfile" "$destfile" 2>/dev/null || true
  chmod --reference="$srcfile" "$destfile" 2>/dev/null || true

  # Preserve timestamps (access & modification)
  touch -r "$srcfile" "$destfile"
done
