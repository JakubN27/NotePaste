#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/NotePaste Camera.app"
EXECUTABLE="$ROOT_DIR/companion/.build/release/NotePasteCamera"
PLUGIN_RESOURCES="$APP_DIR/Contents/Resources/plugin"

if [[ ! -f "$ROOT_DIR/main.js" ]]; then
  npm --prefix "$ROOT_DIR" run build
fi

swift build -c release --package-path "$ROOT_DIR/companion"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$PLUGIN_RESOURCES"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/NotePasteCamera"
cp "$ROOT_DIR/companion/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/manifest.json" "$PLUGIN_RESOURCES/manifest.json"
cp "$ROOT_DIR/main.js" "$PLUGIN_RESOURCES/main.js"
cp "$ROOT_DIR/styles.css" "$PLUGIN_RESOURCES/styles.css"
cp "$ROOT_DIR/versions.json" "$PLUGIN_RESOURCES/versions.json"
chmod +x "$APP_DIR/Contents/MacOS/NotePasteCamera"

echo "$APP_DIR"
