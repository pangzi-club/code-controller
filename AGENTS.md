# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

An AppKit macOS desktop app template built with SwiftPM only — there is no
`.xcodeproj` and no nib; every window, menu and view is constructed in code.
Targets macOS 13+ with Swift tools 5.9. The demo app is a small file browser;
replace its domain code when forking the template.

The package has two targets: a **library** (`DemoExplorer`, all the window
controllers, view controllers, models, stores and helpers) and a thin
**executable** (`DemoExplorerApp`, just the `@main` entry point). The split
lets the test target `@testable import DemoExplorer` and keeps the
`Sources/<Library>` + `Sources/<Library>App` layout `Scripts/rename.sh`
relies on. AppKit has no Xcode Previews — verify UI changes with `make dev`.

## Commands

`make help` lists everything. The ones that matter:

- `make dev` — debug build and run (`swift run`)
- `make test` — run the test suite (`swift test`)
- `make build` — release build
- `make app` — assemble `build/<Display Name>.app` (release build + icon + ad-hoc signing)
- `make launch` — assemble and open the .app
- `make rename NEW=MyApp ID=com.me.MyApp` — full template rename (see below)

## Rules of the codebase

- **`AppInfo.swift` is the single source of truth** for display name, bundle ID
  and version. `Scripts/make-app.sh` and the Makefile parse it with sed, and the
  target/binary name is derived from `Package.swift`. Never hardcode the app
  name or bundle ID anywhere else, and keep the three constants as plain
  single-line string literals — scripts parse them.
- **All user-facing strings go through `l10n()`** (menu titles included), with
  the English key as the lookup key. Every new key must be added to BOTH
  `Resources/en.lproj/Localizable.strings` and
  `Resources/zh-Hans.lproj/Localizable.strings` in the same change. No
  hardcoded UI strings in views or menus.
- **Docs**: code, comments and `README.md` in English; `README.ZH.md` is the
  Chinese mirror — update both together.
- **Tests** use Swift Testing (`import Testing`, `@Test`, `#expect`) and live
  in `Tests/DemoExplorerTests/`. Add tests for new logic in `Models.swift`,
  stores, and helpers; view controllers don't need tests in this template.
  Suites that share a UserDefaults key are `@Suite(.serialized)` — keep that
  when adding UserDefaults-touching tests, Swift Testing runs in parallel.
- **State** lives in `ObservableObject` stores (`SettingsStore`, `FolderStore`)
  persisted to UserDefaults and passed by hand (no environment objects in
  AppKit — wire updates with Combine `sink`s and target/action). The theme is
  applied app-wide by setting `NSApp.appearance` from `AppDelegate`. The main
  window frame persists through `MainWindowController`'s `NSWindowDelegate`
  callbacks — manual save/restore under the fixed UserDefaults key
  `mainWindowFrame`, bypassing NSWindow autosave so `swift run` and the .app
  behave identically. The pure logic in `WindowFramePersistence` (parse /
  restorable / clamp / default / launch frame) has tests.
- **Access control**: the executable target (`Sources/DemoExplorerApp/`) only
  instantiates `AppDelegate`, which is the single `public` type; everything
  else in `Sources/DemoExplorer/` stays internal and is tested via
  `@testable`.
- **The menu bar is built in code** in `AppDelegate.buildMainMenu()` — there is
  no MainMenu.xib because SwiftPM can't ship one. New menu items must use
  `l10n()` titles and add their keys to both `.strings` files.
- **The main window's unified toolbar is managed by `MainWindowController`**
  (`NSToolbarDelegate`) and holds only the sidebar toggle (⌥⌘S resolves to the
  split view controller's `toggleSidebar`, which collapses the sidebar item).
  Reveal/refresh live in row context menus, not the toolbar. Toolbar and menu
  items use nil targets so actions resolve down the responder chain. Sidebar
  cells bake their selected-state styling in, so `syncRowSelection` reloads
  the rows whose selection changed.

## Gotchas

- `swift run` executes a bare binary, so Launch Services treats it as a
  background process: **no Dock icon and no menu bar**. That is expected; use
  `make launch` for the real app experience.
- SwiftPM **lowercases `.lproj` directory names** in the built resource bundle
  and `Bundle` lookup is case-sensitive, so the stock matching never finds
  `zh-hans.lproj` for a `zh-Hans` user. `L10n.swift` resolves the language via
  `Locale.preferredLanguages` and loads the `.lproj` bundle explicitly — do not
  replace it with `Bundle.localizedString` or `String(localized:)`.
- UserDefaults live under the bundle ID, so state saved during `swift run`
  does not carry over to the .app (different domain), and vice versa.
- After renaming the target or touching `Package.swift` heavily, stale
  `.build` caches can produce confusing errors — `make clean`.
- Context menus on rows come from `ContextMenuTableView` (the stock per-row
  menu mechanism is nib-based, which this package can't ship). Row views in
  both tables are rebuilt per `tableView(_:viewFor:row:)` call — fine at
  sidebar/demo scale, add reuse if a table grows.

## Using the template / renaming

`./Scripts/rename.sh NewName com.example.newid` renames everything in one
shot: `Package.swift`, the `Sources/`/`Tests/` directories (the executable
target becomes `NewNameApp`), the `@main` entry point, `AppInfo.swift`
identity, READMEs and this file. The Makefile and `make-app.sh` discover
`AppInfo.swift` via `Sources/*/AppInfo.swift`, so they keep working across
renames. The bundle ID defaults to `com.example.<NewName>` when omitted.
