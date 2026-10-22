# FileBrowser

[English](README.md) | [中文](README.ZH.md)

A simple macOS file browser built with SwiftUI and SwiftPM — no Xcode project needed.

## Features

- **Sidebar**: add folders with the "Add Folder" button or by dragging them in; right-click to remove or reveal in Finder. Each folder gets a stable color tile derived from its path.
- **File list**: card-style list of the selected folder's direct children (directories first, then by name) with system icons, file size, and modification date. Hover highlighting included.
- **Opening files**: double-click a file to open it with the system default app; the context menu also offers "Open" and "Show in Finder".
- **Localization**: English and Simplified Chinese, following the system language.
- The first folder is selected automatically at launch, and the folder list is persisted to UserDefaults (stale paths are dropped).
- Adapts to light and dark appearance.

## Running

For quick development iterations:

```bash
swift run
```

Note that `swift run` executes a bare binary, which Launch Services treats as a
background process — no Dock icon and no menu bar of its own.

There is also a `Makefile` with npm-scripts style shortcuts: `make dev` (debug
run), `make app` (assemble the .app), `make launch` (assemble + open),
`make build`, `make clean`. Run `make help` to list them.

## Packaging as a .app

For the proper experience (Dock icon, menu bar, Cmd+Tab, double-clickable in
Finder), assemble an app bundle:

```bash
./Scripts/make-app.sh          # result: build/FileBrowser.app
open build/FileBrowser.app
```

The script builds the release binary, generates the app icon
(`Scripts/make-icon.swift` draws it programmatically), and ad-hoc code signs the
bundle. App identity lives in `Sources/FileBrowser/AppInfo.swift` — the script
reads the display name, bundle ID and version from there, and derives the
target/binary name from `Package.swift`, so nothing is duplicated. The .app
stores preferences under its bundle ID, so folders saved during `swift run`
sessions won't carry over.

## Project Layout

```
Sources/FileBrowser/
├── FileBrowserApp.swift   # App entry point and window scene
├── AppInfo.swift          # Display name / bundle ID / version (single source of truth)
├── ContentView.swift      # Split layout, sidebar, placeholder
├── FileListView.swift     # Card-style file list
├── FolderStore.swift      # Sidebar folder list + persistence
├── Models.swift           # File loading, open/reveal helpers, folder picker
├── L10n.swift             # Localization helpers
├── Resources/
│   ├── en.lproj/Localizable.strings
│   └── zh-Hans.lproj/Localizable.strings
Scripts/
├── make-app.sh            # Release build + .app bundle assembly
└── make-icon.swift        # Programmatic app icon generator
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against `Locale.preferredLanguages` and loads the matching `.lproj`
bundle explicitly to work around this.
