# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

A SwiftUI + SwiftPM template for macOS desktop apps, demonstrated by a simple
file browser — no Xcode project needed.

## Features

- **Sidebar**: add folders with the "Add Folder" button or by dragging them in; right-click to remove or reveal in Finder. Each folder gets a stable color tile derived from its path.
- **File list**: card-style list of the selected folder's direct children (directories first, then by name) with system icons, file size, and modification date. Hover highlighting included.
- **Opening files**: double-click a file to open it with the system default app; the context menu also offers "Open" and "Show in Finder".
- **Settings page**: system/light/dark theme picker, persisted and applied app-wide.
- **Persistence**: the folder list lives in UserDefaults (stale paths are dropped), and the window frame survives relaunches.
- **Localization**: English and Simplified Chinese, following the system language.
- Adapts to light and dark appearance.

## Running

For quick development iterations:

```bash
swift run
```

Note that `swift run` executes a bare binary, which Launch Services treats as a
background process — no Dock icon and no menu bar of its own.

Run the test suite (Swift Testing) with:

```bash
swift test    # or: make test
```

There is also a `Makefile` with npm-scripts style shortcuts: `make dev` (debug
run), `make test`, `make app` (assemble the .app), `make launch` (assemble +
open), `make build`, `make lint` / `make format` (SwiftLint), `make rename`
(template rename), `make clean`. Run `make help` to list them.

## Using This as a Template

To start a new app from this repository, rename everything in one shot:

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

This renames the package and target in `Package.swift`, moves `Sources/` and
`Tests/`, renames the `@main` struct, and updates the identity in
`AppInfo.swift` (the bundle ID defaults to `com.example.<NewName>` when
omitted), the READMEs and `AGENTS.md`. The display name can then be tuned
freely in `AppInfo.swift` — it may contain spaces. `AGENTS.md` also documents
the conventions and known gotchas of this codebase.

## Packaging as a .app

For the proper experience (Dock icon, menu bar, Cmd+Tab, double-clickable in
Finder), assemble an app bundle:

```bash
./Scripts/make-app.sh          # result: build/DemoExplorer.app
open build/DemoExplorer.app
```

The script builds the release binary, generates the app icon
(`Scripts/make-icon.swift` draws it programmatically), and ad-hoc code signs the
bundle. App identity lives in `Sources/DemoExplorer/AppInfo.swift` — the script
reads the display name, bundle ID and version from there, and derives the
target/binary name from `Package.swift`, so nothing is duplicated. The .app
stores preferences under its bundle ID, so folders saved during `swift run`
sessions won't carry over.

## Project Layout

```
Sources/DemoExplorer/
├── DemoExplorerApp.swift        # App entry point and window scene
├── AppInfo.swift                # Display name / bundle ID / version (single source of truth)
├── ContentView.swift            # Split layout, sidebar, settings entry
├── FileListView.swift           # Card-style file list
├── FolderStore.swift            # Sidebar folder list + persistence
├── Models.swift                 # File loading, open/reveal helpers, folder picker
├── L10n.swift                   # Localization helpers
├── SettingsStore.swift          # Theme preference + persistence
├── SettingsView.swift           # Settings page (theme picker)
├── WindowFrameAutosaver.swift   # Stable window frame autosave
├── Resources/
│   ├── en.lproj/Localizable.strings
│   └── zh-Hans.lproj/Localizable.strings
Tests/DemoExplorerTests/         # Swift Testing suite
Scripts/
├── make-app.sh                  # Release build + .app bundle assembly
├── make-icon.swift              # Programmatic app icon generator
└── rename.sh                    # One-shot template rename
AGENTS.md                        # Conventions and gotchas for humans and agents
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against `Locale.preferredLanguages` and loads the matching `.lproj`
bundle explicitly to work around this.
