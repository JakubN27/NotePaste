# Distribution

NotePaste has two runtime pieces:

- `NotePaste` Obsidian plugin: `manifest.json`, `main.js`, `styles.css`, `versions.json`
- `NotePaste Camera.app`: native macOS companion for Continuity Camera

The current release packaging still produces a standalone plugin zip, but the native app now also embeds the plugin files and can install or update the plugin in selected vaults. The intended polished distribution is a signed `NotePaste.app` installer with a cleaner first-run experience.

## Current Release Artifacts

Run:

```bash
npm run package:release
```

This creates:

```text
dist/release/notepaste-obsidian-plugin-<version>.zip
dist/release/NotePaste-Camera-<version>.zip
dist/release/NotePaste-Camera-<version>.dmg
dist/release/checksums.txt
```

The plugin zip is for manual Obsidian installation. The companion zip contains the native macOS app plus bundled plugin files under `Contents/Resources/plugin`. The `.dmg` is the preferred user-facing download until the app is signed and notarized.

## Manual Install

Install the plugin into a vault:

```bash
npm run install:vault -- "/path/to/vault"
```

Install the companion:

```bash
open "dist/NotePaste Camera.app"
```

For normal users, prefer copying `NotePaste Camera.app` to `/Applications` or `~/Applications`, opening it, selecting a vault, and clicking `Install / Update Plugin`. Opening it once also registers `notepaste-camera://`.

## Signed Distribution Roadmap

1. Rename the companion into the primary `NotePaste.app` product.
2. Improve first-launch install UX with multi-vault selection and clearer Obsidian reload guidance.
3. Add update detection so users can see which vaults already have NotePaste installed.
4. Code sign and notarize the app.
5. Ship a `.dmg` with the app and short install instructions.

## Obsidian Community Plugin Notes

The plugin can be submitted to the Obsidian community plugin directory, but the native macOS companion cannot be installed by the community plugin store in a clean way. Community plugin distribution should be treated as an optional install path after the signed app installer is ready.
