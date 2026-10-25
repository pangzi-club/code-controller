# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

A SwiftUI macOS desktop app template built with SwiftPM only — there is no
`.xcodeproj`. Targets macOS 13+ with Swift tools 5.9. The demo app is a small
file browser; replace its domain code when forking the template.

The package has two targets: a **library** (`DemoExplorer`, all the views,
models, stores and helpers) and a thin **executable** (`DemoExplorerApp`, just
the `@main` entry point). Splitting them lets Xcode Previews work — open
`Package.swift` in Xcode and preview with the library scheme; previews require
a library product, not a command-line tool.

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
- **All user-facing strings go through `l10n()` / `l10nString()`** with the
  English key as the lookup key. Every new key must be added to BOTH
  `Resources/en.lproj/Localizable.strings` and
  `Resources/zh-Hans.lproj/Localizable.strings` in the same change. No
  hardcoded UI strings in views.
- **Docs**: code, comments and `README.md` in English; `README.ZH.md` is the
  Chinese mirror — update both together.
- **Tests** use Swift Testing (`import Testing`, `@Test`, `#expect`) and live
  in `Tests/DemoExplorerTests/`. Add tests for new logic in `Models.swift`,
  stores, and helpers; views don't need snapshot tests in this template.
  Suites that share a UserDefaults key are `@Suite(.serialized)` — keep that
  when adding UserDefaults-touching tests, Swift Testing runs in parallel.
- **State** lives in `ObservableObject` stores (`SettingsStore`, `FolderStore`)
  persisted to UserDefaults and injected via `.environmentObject`. The main
  window frame persists through `WindowFrameAutosaver` — manual save/restore
  under the fixed UserDefaults key `mainWindowFrame`, bypassing NSWindow
  autosave so `swift run` and the .app behave identically. The pure logic in
  `WindowFramePersistence` (parse / restorable / clamp / default) has tests.
- **Settings is a separate window**, not a page inside the main window: the
  SwiftUI `Settings` scene (standard ⌘, preferences window — singleton,
  non-resizable, auto-centered). The sidebar gear opens it through
  `SettingsWindowOpener`, which sends `showSettingsWindow:` down the
  responder chain — undocumented but the only macOS 13 route; the public
  `openSettings` environment action requires macOS 14.
- **Access control**: the library target (`Sources/DemoExplorer/`) must mark
  types and members `public` when the executable target
  (`Sources/DemoExplorerApp/`) uses them. Protocol requirements (`body`,
  `makeNSView`, `updateNSView`, …) on public types must also be `public`.

## Gotchas

- `swift run` executes a bare binary, so Launch Services treats it as a
  background process: **no Dock icon and no menu bar**. That is expected; use
  `make launch` for the real app experience.
- SwiftPM **lowercases `.lproj` directory names** in the built resource bundle
  and `Bundle` lookup is case-sensitive, so the stock matching never finds
  `zh-hans.lproj` for a `zh-Hans` user. `L10n.swift` resolves the language
  against the Settings override (if one is stored) and
  `Locale.preferredLanguages`, and loads the `.lproj` bundle explicitly — do
  not replace it with `Bundle.localizedString` or `String(localized:)`. The
  UI language is fixed at launch (strings are baked into views when they are
  built), so the language setting applies on relaunch.
- UserDefaults live under the bundle ID, so state saved during `swift run`
  does not carry over to the .app (different domain), and vice versa.
- After renaming the target or touching `Package.swift` heavily, stale
  `.build` caches can produce confusing errors — `make clean`.

## Using the template / renaming

`./Scripts/rename.sh NewName com.example.newid` renames everything in one
shot: `Package.swift`, the `Sources/`/`Tests/` directories (the executable
target becomes `NewNameApp`), the `@main` struct, `AppInfo.swift` identity,
READMEs and this file. The Makefile and `make-app.sh` discover `AppInfo.swift`
via `Sources/*/AppInfo.swift`, so they keep working across renames. The bundle
ID defaults to `com.example.<NewName>` when omitted.
