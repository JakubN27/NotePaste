# Distribution

NotePaste has two runtime pieces:

- `NotePaste` Obsidian plugin: `manifest.json`, `main.js`, `styles.css`, `versions.json`
- `NotePaste Camera.app`: native macOS companion for Continuity Camera

The current release packaging keeps those pieces separate but builds them from one repo. The intended polished distribution is a signed `NotePaste.app` installer that embeds the plugin files and installs them into selected vaults.

## Current Release Artifacts

Run:

```bash
npm run package:release
```

This creates:

```text
dist/release/notepaste-obsidian-plugin-<version>.zip
dist/release/NotePaste-Camera-<version>.zip
dist/release/checksums.txt
```

The plugin zip is for manual Obsidian installation. The companion zip contains the native macOS app.

## Manual Install

Install the plugin into a vault:

```bash
npm run install:vault -- "/path/to/vault"
```

Install the companion:

```bash
open "dist/NotePaste Camera.app"
```

For normal users, prefer copying `NotePaste Camera.app` to `/Applications` or `~/Applications` and opening it once so macOS registers `notepaste-camera://`.

## Signed Distribution Roadmap

1. Convert the companion into the primary `NotePaste.app` product.
2. Embed the plugin release files in `NotePaste.app/Contents/Resources/plugin`.
3. Add first-launch vault discovery using Obsidian's vault registry.
4. Let users select one or more vaults and install/update the plugin automatically.
5. Code sign and notarize the app.
6. Ship a `.dmg` with the app and short install instructions.

## Obsidian Community Plugin Notes

The plugin can be submitted to the Obsidian community plugin directory, but the native macOS companion cannot be installed by the community plugin store in a clean way. Community plugin distribution should be treated as an optional install path after the signed app installer is ready.
