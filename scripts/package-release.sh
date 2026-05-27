#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
RELEASE_DIR="$ROOT_DIR/dist/release"
PLUGIN_STAGING="$RELEASE_DIR/notepaste"
PLUGIN_ZIP="$RELEASE_DIR/notepaste-obsidian-plugin-$VERSION.zip"
COMPANION_ZIP="$RELEASE_DIR/NotePaste-Camera-$VERSION.zip"
COMPANION_DMG="$RELEASE_DIR/NotePaste-Camera-$VERSION.dmg"
DMG_STAGING="$RELEASE_DIR/dmg"

cd "$ROOT_DIR"

PACKAGE_VERSION="$VERSION" node <<'NODE'
const fs = require("node:fs");
const version = process.env.PACKAGE_VERSION;
const manifest = JSON.parse(fs.readFileSync("manifest.json", "utf8"));
const versions = JSON.parse(fs.readFileSync("versions.json", "utf8"));
const plist = fs.readFileSync("companion/Info.plist", "utf8");

if (manifest.version !== version) {
  throw new Error(`manifest.json version ${manifest.version} does not match package.json ${version}`);
}
if (!versions[version]) {
  throw new Error(`versions.json is missing ${version}`);
}
if (!plist.includes(`<string>${version}</string>`)) {
  throw new Error(`companion/Info.plist does not contain version ${version}`);
}
NODE

npm run build:all

rm -rf "$RELEASE_DIR"
mkdir -p "$PLUGIN_STAGING"

cp "$ROOT_DIR/manifest.json" "$PLUGIN_STAGING/manifest.json"
cp "$ROOT_DIR/main.js" "$PLUGIN_STAGING/main.js"
cp "$ROOT_DIR/styles.css" "$PLUGIN_STAGING/styles.css"
cp "$ROOT_DIR/versions.json" "$PLUGIN_STAGING/versions.json"

(
  cd "$RELEASE_DIR"
  /usr/bin/ditto -c -k --norsrc --keepParent "notepaste" "$(basename "$PLUGIN_ZIP")"
)

(
  cd "$ROOT_DIR/dist"
  /usr/bin/ditto -c -k --norsrc --keepParent "NotePaste Camera.app" "$COMPANION_ZIP"
)

mkdir -p "$DMG_STAGING"
/usr/bin/ditto --norsrc "$ROOT_DIR/dist/NotePaste Camera.app" "$DMG_STAGING/NotePaste Camera.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "NotePaste Camera" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$COMPANION_DMG" >/dev/null

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$PLUGIN_ZIP")" "$(basename "$COMPANION_ZIP")" "$(basename "$COMPANION_DMG")" > checksums.txt
)

echo "$PLUGIN_ZIP"
echo "$COMPANION_ZIP"
echo "$COMPANION_DMG"
echo "$RELEASE_DIR/checksums.txt"
