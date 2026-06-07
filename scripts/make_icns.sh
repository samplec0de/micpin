#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/AppIcon-1024.png"
DIST="$ROOT/dist"
ICONSET="$DIST/AppIcon.iconset"
ICNS="$DIST/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
    echo "Missing $SRC" >&2
    exit 1
fi

mkdir -p "$DIST"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# size -> iconset filename (Apple-required set, 16…1024)
gen() { sips -z "$1" "$1" "$SRC" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"
echo "Built $ICNS"
