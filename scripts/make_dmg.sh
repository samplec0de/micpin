#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MicPin"
VERSION="0.1.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

# Build the .app first if it isn't there.
if [[ ! -d "$APP" ]]; then
    "$ROOT/scripts/bundle.sh"
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/$APP_NAME.app"
# Drag-to-install: an Applications shortcut next to the app.
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"
echo "Built $DMG"
