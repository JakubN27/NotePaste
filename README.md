# NotePaste

NotePaste inserts iPhone photos directly into the active Obsidian note. Type `/notepaste`, take a photo through Apple Continuity Camera, and the image is saved into the vault and embedded at the cursor.

The project currently builds two runtime pieces from one repo:

- A desktop-only Obsidian plugin that owns the active note, placeholder, local receiver, attachment save, and embed insertion.
- A native macOS companion app that opens the system Continuity Camera flow and sends the returned image back to the plugin.

For distribution, the native app now embeds the plugin files and can install or update the plugin in a detected Obsidian vault. The standalone plugin zip is still produced for development and fallback installs.

## Status

This is an early macOS/iPhone prototype. It works locally, and the app has first-pass one-install scaffolding. Public distribution still needs signing, notarization, and a polished installer flow.

## Requirements

- macOS with Apple Continuity Camera support
- iPhone signed into the same Apple Account with Handoff enabled
- Obsidian Desktop
- Node.js 22 for development
- Swift 6 / Xcode Command Line Tools for building the companion

## Development

```bash
npm install
npm test
npm run build:all
```

Build outputs:

```text
main.js
dist/NotePaste Camera.app
```

Install the plugin into a local vault from source:

```bash
npm run install:vault -- "/path/to/vault"
```

Register and open the companion app:

```bash
open "dist/NotePaste Camera.app"
```

## Usage

1. Open `NotePaste Camera.app`.
2. Choose an Obsidian vault and click `Install / Update Plugin`.
3. Reload Obsidian if it was already open.
4. Open a note and type `/notepaste`, or run `Start NotePaste capture` from the command palette.
5. In `NotePaste Camera`, choose the iPhone camera option.
6. Take the photo and tap `Use Photo`.
7. The image is saved into the configured attachments folder and embedded in the note.

## Release Packaging

Create local release artifacts:

```bash
npm run package:release
```

Artifacts are written to:

```text
dist/release/notepaste-obsidian-plugin-<version>.zip
dist/release/NotePaste-Camera-<version>.zip
dist/release/NotePaste-Camera-<version>.dmg
dist/release/checksums.txt
```

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for the distribution plan and one-install roadmap.

## Repository Notes

- `main.js` is generated and intentionally ignored.
- `dist/` and `companion/.build/` are generated and intentionally ignored.
- GitHub CI builds both the plugin and native companion on macOS.

## License

MIT
