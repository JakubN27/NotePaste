#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/NotePaste Camera.app"
EXECUTABLE="$ROOT_DIR/companion/.build/release/NotePasteCamera"

swift build -c release --package-path "$ROOT_DIR/companion"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/NotePasteCamera"
cp "$ROOT_DIR/companion/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/NotePasteCamera"

echo "$APP_DIR"
