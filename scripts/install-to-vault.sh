#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: npm run install:vault -- /path/to/vault" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$1"
PLUGIN_DIR="$VAULT_DIR/.obsidian/plugins/notepaste"
COMMUNITY_PLUGINS="$VAULT_DIR/.obsidian/community-plugins.json"

if [[ ! -d "$VAULT_DIR/.obsidian" ]]; then
  echo "Not an Obsidian vault: $VAULT_DIR" >&2
  exit 1
fi

npm run build

mkdir -p "$PLUGIN_DIR"
cp "$ROOT_DIR/manifest.json" "$PLUGIN_DIR/manifest.json"
cp "$ROOT_DIR/main.js" "$PLUGIN_DIR/main.js"
cp "$ROOT_DIR/styles.css" "$PLUGIN_DIR/styles.css"

COMMUNITY_PLUGINS="$COMMUNITY_PLUGINS" node <<'NODE'
const fs = require("node:fs");
const path = process.env.COMMUNITY_PLUGINS;
let plugins = [];

if (fs.existsSync(path)) {
  plugins = JSON.parse(fs.readFileSync(path, "utf8"));
}
if (!plugins.includes("notepaste")) {
  plugins.push("notepaste");
}
fs.writeFileSync(path, JSON.stringify(plugins, null, 2) + "\n");
NODE

echo "Installed NotePaste into $PLUGIN_DIR"
