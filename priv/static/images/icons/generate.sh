#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/app-icon.svg"
LOGO="$ROOT/../logo.svg"

cp "$SRC" "$LOGO"

for size in 16 32 48 180 192 512; do
  convert -background none -resize "${size}x${size}" "$SRC" "PNG32:$ROOT/icon-${size}.png"
done

convert "$ROOT/icon-16.png" "$ROOT/icon-32.png" "$ROOT/icon-48.png" "$ROOT/../../favicon.ico"