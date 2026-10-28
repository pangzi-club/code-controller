# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

A SwiftUI + SwiftPM template for macOS desktop apps, demonstrated by a simple
file browser — no Xcode project needed. The package splits into a library
(all app code) and a thin `@main` executable, so Xcode Previews work out of
the box.

## Features

- **Sidebar**: add folders with the "Add Folder" button or by dragging them in; right-click to remove or reveal in Finder. Each folder gets a stable color tile derived from its path.
- **File list**: card-style list of the selected folder's direct children (directories first, then by name) with system icons, file size, and modification date. Hover highlighting included.
- **Opening files**: double-click a file to open it with the system default app; the context menu also offers "Open" and "Show in Finder".
- **Settings window**: system/light/dark theme picker and an interface language picker (system/English/简体中文), persisted and applied app-wide — a separate fixed-size window opened with ⌘, (App menu) or the sidebar gear.
- **Persistence**: the folder list lives in UserDefaults (stale paths are dropped), and the window frame survives relaunches.
- **Localization**: English and Simplified Chinese, following the system language by default with an override in Settings (takes effect on relaunch).
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
open), `make build`, `make rename` (template rename), `make clean`. Run
`make help` to list them.

## Xcode Previews

Open `Package.swift` in Xcode (it synthesizes the schemes; `.swiftpm/` is
gitignored). The package has two targets: the **DemoExplorer** library with
all views, models and stores, and the **DemoExplorerApp** executable that only
holds the `@main` entry point. Previews need a library product — a
command-line-tool target cannot power the canvas — so the views (each file
ends in a `#Preview` block) preview against the library scheme. Types used by
the executable target must be `public`.

## Using This as a Template

To start a new app from this repository, rename everything in one shot:

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

This renames the package and targets in `Package.swift`, moves `Sources/` and
`Tests/` (the executable target becomes `MyAppApp`), renames the `@main`
struct, and updates the identity in `AppInfo.swift` (the bundle ID defaults to
`com.example.<NewName>` when omitted), the READMEs and `AGENTS.md`. The display
name can then be tuned freely in `AppInfo.swift` — it may contain spaces.
`AGENTS.md` also documents the conventions and known gotchas of this codebase.

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
sessions won't carry over. `CFBundleLocalizations` is declared in the generated
`Info.plist` so the standard AppKit menus follow the in-app language.

If the app reads protected folders, add the matching `NS*UsageDescription` keys
to the Info.plist heredoc in `Scripts/make-app.sh`, and localized copies in
`Contents/Resources/<lang>.lproj/InfoPlist.strings` so the system prompt follows
the user's language. Each rebuild re-signs the ad-hoc bundle, which changes the
code identity macOS associates with TCC decisions — a fresh build may prompt
again even if access was already granted.

## Project Layout

```
Sources/
├── DemoExplorer/                 # Library target: all views, models, stores
│   ├── AppInfo.swift             # Display name / bundle ID / version (single source of truth)
│   ├── ContentView.swift         # Split layout with sidebar and detail pane
│   ├── FileListView.swift        # Card-style file list
│   ├── FolderStore.swift         # Sidebar folder list + persistence
│   ├── Models.swift              # File loading, open/reveal helpers, folder picker
│   ├── L10n.swift                # Localization helpers
│   ├── SettingsStore.swift       # Theme + language preferences and persistence
│   ├── SettingsView.swift        # Settings window content (theme + language pickers)
│   ├── WindowFrameAutosaver.swift # Manual window frame save/restore (tested pure logic)
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── zh-Hans.lproj/Localizable.strings
└── DemoExplorerApp/
    └── DemoExplorerApp.swift     # Thin @main entry point and window scene
Tests/DemoExplorerTests/          # Swift Testing suite
Scripts/
├── make-app.sh                   # Release build + .app bundle assembly
├── make-icon.swift               # Programmatic app icon generator
└── rename.sh                     # One-shot template rename
AGENTS.md                         # Conventions and gotchas for humans and agents
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against the Settings override (if one is stored) and
`Locale.preferredLanguages`, and loads the matching `.lproj` bundle explicitly
to work around this. The language is fixed at launch — strings are baked into
views when they are built — so a changed setting asks to be relaunched before
it applies.
