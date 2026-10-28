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
- `make check-l10n` — verify both `Localizable.strings` files have the same keys
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
  hardcoded UI strings in views. Run `make check-l10n` after touching either
  file — it reports missing and duplicate keys.
- **Docs**: code, comments and `README.md` in English; `README.ZH.md` is the
  Chinese mirror — update both together. `docs/ui-testing.md` is the AX +
  `screencapture` + CGEvent playbook for verifying the assembled `.app`:
  window frame restoration, the settings window, focus rings, empty states,
  dark mode and localization.
- **Tests** use Swift Testing (`import Testing`, `@Test`, `#expect`) and live
  in `Tests/DemoExplorerTests/`. Add tests for new logic in `Models.swift`,
  stores, and helpers; views don't need snapshot tests in this template.
  Suites that share a UserDefaults key are `@Suite(.serialized)` — keep that
  when adding UserDefaults-touching tests, Swift Testing runs in parallel.
  File-system tests build their fixtures under
  `FileManager.temporaryDirectory`; never touch the real home directory.
- **State** lives in `ObservableObject` stores (`SettingsStore`, `FolderStore`)
  persisted to UserDefaults and injected via `.environmentObject`. The main
  window frame persists through `WindowFrameAutosaver` — manual save/restore
  under the fixed UserDefaults key `mainWindowFrame`, bypassing NSWindow
  autosave so `swift run` and the .app behave identically. It captures the
  window synchronously in `viewWillMove(toWindow:)`, hides it, restores the
  frame, then reveals it, so SwiftUI's default size never flashes. The pure
  logic in `WindowFramePersistence` (parse / restorable / clamp / default) has
  tests.
- **Settings is a separate window**, not a page inside the main window: a
  single-instance `Window` scene (`id: "settings"`, fixed content size,
  centered). The sidebar gear opens it via `@Environment(\.openWindow)`;
  the ⌘, menu item (`CommandGroup(replacing: .appSettings)`) posts the
  `openSettingsWindow` notification, which ContentView forwards to
  `openWindow` — commands can't reach the environment action themselves.
  Do NOT switch to a `Settings` scene: opening it programmatically is
  macOS 14+ API, and its undocumented `showSettingsWindow:` selector was
  verified to do nothing here.
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
  `Locale.preferredLanguages`, and loads the explicit `en` or `zh-Hans`
  `.lproj` bundle — asking the multi-localization module bundle would fall
  back to the system language and ignore an English override on a Chinese
  system. Do not replace this with `Bundle.localizedString` or
  `String(localized:)`. The UI language is fixed at launch (strings are baked
  into views when they are built), so the language setting applies on relaunch.
- The **NavigationSplitView sidebar toggle keeps its focus ring** once it has
  keyboard focus — clicked or from launch — and nothing in the detail pane is
  focusable to take over, so the ring never clears by itself. ContentView
  routes the split view's `columnVisibility` through a custom binding that
  calls `makeFirstResponder(nil)` on every toggle, and once on appear.
- SwiftUI shows a `WindowGroup` window at its own size before any async frame
  restore lands, so a plain async `setFrame` makes the window visibly jump on
  launch. `WindowFrameAutosaver` captures the window in
  `viewWillMove(toWindow:)`, sets `alphaValue = 0`, restores the frame, then
  reveals it. Keep that ordering; hiding after the restore has no effect.
- SwiftUI `@FocusState` does not move first responder into a toolbar
  `TextField` on macOS. Wrap an `NSSearchField` in an `NSViewRepresentable`
  and call `makeFirstResponder` whenever its focus token changes; have the
  ⌘F menu item post a notification that bumps that token.
- Ad-hoc re-signing (`make app`) changes the code identity macOS associates
  with TCC decisions, so a rebuild may re-prompt for protected-folder access
  even if it was already granted. That is expected for local builds; do not
  work around it by disabling TCC checks.
- Standard AppKit menus only localize when the app bundle declares
  `CFBundleLocalizations`; `Scripts/make-app.sh` writes it. If the app uses
  TCC-protected folders, add the matching usage descriptions to the Info.plist
  heredoc and localized copies under
  `Contents/Resources/<lang>.lproj/InfoPlist.strings`.
- UserDefaults live under the bundle ID, so state saved during `swift run`
  does not carry over to the .app (different domain), and vice versa.
- After renaming the target or touching `Package.swift` heavily, stale
  `.build` caches can produce confusing errors — `make clean`.

## Using the template / renaming

`./Scripts/rename.sh NewName com.example.newid` renames everything in one
shot: `Package.swift`, the `Sources/`/`Tests/` directories (the executable
target becomes `NewNameApp`), the `@main` struct, `AppInfo.swift` identity,
READMEs, `AGENTS.md` and `docs/`. It finishes by listing any file that still
contains the old name, so configs or scripts added later are visible instead
of silently stale. The Makefile and `make-app.sh` discover `AppInfo.swift`
via `Sources/*/AppInfo.swift`, so they keep working across renames. The bundle
ID defaults to `com.example.<NewName>` when omitted.

## Recipe: sidebar under the titlebar

The template ships an opaque toolbar; a sidebar that reaches the traffic
lights needs four coordinated changes:

- Set `fullSizeContentView` and `titlebarAppearsTransparent` on the window.
- Hide the window toolbar background so the sidebar material reaches the
  traffic lights; do not paint an opaque background over the sidebar.
- `NavigationSplitView` adds its own top inset on top of the titlebar safe
  area, so the sidebar ignores the top safe area and reserves the
  traffic-light strip in its own content padding — otherwise the top spacing
  doubles.
- Overlay the page color on the detail column at the root's top safe-area
  inset so scrolled content does not show through the toolbar controls.
  Panels that start below the toolbar must not ignore the top safe area.
