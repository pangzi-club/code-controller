# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

An AppKit + SwiftPM template for macOS desktop apps, demonstrated by a simple
file browser — no Xcode project, no nibs. All windows, menus and views are
built in code. The package splits into a library (all app code) and a thin
`@main` executable, so the test target can import everything via `@testable`.

## Features

- **Sidebar**: a folder table with rounded accent selection and hover highlight; add folders with the "Add Folder" button or by dragging them in; right-click to remove or reveal in Finder. Each folder gets a stable color tile derived from its path.
- **File list**: card-style list of the selected folder's direct children (directories first, then by name) with system icons, file size, and modification date. Native selection semantics: click to select, arrow keys to navigate, double-click / Return / ⌘O to open; the context menu offers "Open" and "Show in Finder". The list watches the folder on disk and refreshes itself (keeping the selection) when its contents change.
- **Settings window**: system/light/dark theme picker, persisted and applied app-wide, opened with ⌘, like a proper macOS preferences window.
- **Menu bar & toolbar**: the menu bar is built programmatically in `AppDelegate` — About, Settings, Hide/Hide Others/Show All, Quit, plus File (Open ⌘O), Edit (Undo/Redo/Cut/Copy/Paste/Select All/Services/Emoji & Symbols), View (Toggle Sidebar ⌥⌘S), Window and Help. The window shows a unified toolbar with the sidebar toggle and the folder name as the inline title; no MainMenu.xib is needed.
- **Persistence**: the folder list lives in UserDefaults (stale paths are dropped), and the window frame survives relaunches.
- **Localization**: English and Simplified Chinese, following the system language — including every menu title.
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

## Library / Executable Split

The package has two targets: the **DemoExplorer** library with all window
controllers, view controllers, models and stores, and the **DemoExplorerApp**
executable that only holds the `@main` entry point. The split keeps the app
code importable by the test target (`@testable import DemoExplorer`) and keeps
the `Sources/<Library>` + `Sources/<Library>App` layout `Scripts/rename.sh`
relies on. The only type the executable touches is `AppDelegate`, which is
therefore the only `public` type.

## Using This as a Template

To start a new app from this repository, rename everything in one shot:

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

This renames the package and targets in `Package.swift`, moves `Sources/` and
`Tests/` (the executable target becomes `MyAppApp`), renames the `@main`
entry point, and updates the identity in `AppInfo.swift` (the bundle ID
defaults to `com.example.<NewName>` when omitted), the READMEs and
`AGENTS.md`. The display name can then be tuned freely in `AppInfo.swift` — it
may contain spaces. `AGENTS.md` also documents the conventions and known
gotchas of this codebase.

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
Sources/
├── DemoExplorer/                  # Library target: all app code
│   ├── AppInfo.swift              # Display name / bundle ID / version (single source of truth)
│   ├── AppDelegate.swift          # NSApplicationDelegate: menu bar, theme, launch
│   ├── ContextMenuTableView.swift # NSTableView subclass with row context menus
│   ├── FileListViewController.swift # Card-style file list
│   ├── FolderStore.swift          # Sidebar folder list + persistence
│   ├── L10n.swift                 # Localization helpers
│   ├── MainWindowController.swift # Main window, split view, detail pane, frame persistence
│   ├── Models.swift               # File loading, open/reveal helpers, folder picker
│   ├── SettingsStore.swift        # Theme preference + persistence
│   ├── SettingsViewController.swift # Settings window content (theme picker)
│   ├── SettingsWindowController.swift # The ⌘, settings window
│   ├── SidebarViewController.swift  # Sidebar table, drag-and-drop, folder colors
│   ├── StyleSupport.swift           # Background/shadow/badge/dashed-button helpers
│   ├── WindowFramePersistence.swift # Manual window frame save/restore (tested pure logic)
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── zh-Hans.lproj/Localizable.strings
└── DemoExplorerApp/
    └── DemoExplorerApp.swift      # Thin @main entry point
Tests/DemoExplorerTests/           # Swift Testing suite
Scripts/
├── make-app.sh                    # Release build + .app bundle assembly
├── make-icon.swift                # Programmatic app icon generator
└── rename.sh                      # One-shot template rename
AGENTS.md                          # Conventions and gotchas for humans and agents
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against `Locale.preferredLanguages` and loads the matching `.lproj`
bundle explicitly to work around this.
