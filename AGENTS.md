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
- `make app` — assemble `build/<Display Name>.app` (universal release build,
  sandboxed, Developer ID when the keychain has one, otherwise ad-hoc)
- `make mas` — assemble the App Store build and
  `build/<Display Name>-<version>-<build>.pkg` (Apple Distribution;
  `PROVISION_PROFILE` embeds a TestFlight profile)
- `make launch` — assemble and open `build/<Display Name> Dev.app` with bundle
  ID `<bundleID>.dev` and its own TCC grant and sandbox container
- `make rename NEW=MyApp ID=com.me.MyApp` — full template rename (see below)
- `make template-diff SOURCE=/path/to/swiftui-starter` — show drift in
  template-managed files (see `TEMPLATE.md`)

## Rules of the codebase

- **`AppInfo.swift` is the single source of truth** for display name, bundle ID,
  version and build number. `Scripts/make-app.sh` and the Makefile parse it with
  sed, and the target/binary name is derived from `Package.swift`. Never
  hardcode the app name or bundle ID anywhere else, and keep the four constants
  as plain single-line string literals — scripts parse them.
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
- **Logging** goes through `Log` (`Log.swift`) — never `print`. Every call
  writes unified logging (subsystem = `AppInfo.bundleID`) and mirrors to
  `Library/Logs/<displayName>/app.log` (rotated to `app.log.1` at 2 MB per
  launch) — the real `~/Library/Logs/...` for `swift run`, the container's
  `~/Library/Containers/<bundleID>/Data/Library/Logs/...` for the sandboxed
  .app. `Log.bootstrap()` runs from the `@main` initializer and records the
  bundle, sandbox and log paths. Use the matching category (`app`, `files`,
  `window`), and log the underlying error before mapping it to a user-facing
  failure. Stream it with
  `/usr/bin/log stream --predicate 'subsystem == "<bundleID>"' --level debug`
  (the `/usr/bin/` prefix dodges zsh's builtin `log`). Crash reports come from
  macOS: `~/Library/Logs/DiagnosticReports/<executable target>-*.ips`.
- **Tests** use Swift Testing (`import Testing`, `@Test`, `#expect`) and live
  in `Tests/DemoExplorerTests/`. Add tests for new logic in `Models.swift`,
  stores, and helpers; views don't need snapshot tests in this template.
  Suites that share a UserDefaults key are `@Suite(.serialized)` — keep that
  when adding UserDefaults-touching tests, Swift Testing runs in parallel.
  File-system tests build their fixtures under
  `FileManager.temporaryDirectory`; never touch the real home directory.
- **State** lives in `ObservableObject` stores (`SettingsStore`, `FolderStore`)
  persisted to UserDefaults and injected via `.environmentObject`. The folder
  list stores app-scoped security bookmarks under `folderBookmarks` (not plain
  paths), so sandboxed access survives relaunch; `FolderStore` starts each
  scope on launch and stops it when the folder is removed. The main
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
  verified to do nothing here. The window opts out of state restoration
  (`window.isRestorable = false` in `SettingsWindowRestorationDisabler`),
  because a plain `Window` scene would otherwise reopen at launch when it
  was open at quit.
- **Access control**: the library target (`Sources/DemoExplorer/`) must mark
  types and members `public` when the executable target
  (`Sources/DemoExplorerApp/`) uses them. Protocol requirements (`body`,
  `makeNSView`, `updateNSView`, …) on public types must also be `public`.

## Sandbox and distribution

- The app is always signed with `Scripts/App.entitlements`: App Sandbox,
  user-selected read-write and app-scoped bookmarks. Add an entitlement only
  when a feature requires one — App Review sees all of them.
- The sandbox moves Application Support, Caches, Logs and UserDefaults into
  `~/Library/Containers/<bundleID>/Data`. PNGs and other user-selected files
  stay where they are. `swift run` is not sandboxed, so file paths and access
  rules differ; test sandbox behavior with `make app` / `make launch`.
- `AppInfo.build` is the App Store build number: bump it for every upload
  (`CFBundleVersion`); `CFBundleShortVersionString` comes from `version`.
  `LSMinimumSystemVersion` is parsed from `Package.swift`.
- `Sources/*/Resources/PrivacyInfo.xcprivacy` declares the required-reason APIs
  (UserDefaults `CA92.1`; file timestamps `DDA9.1` / `3B52.1` / `C617.1`).
  Update it whenever a new required-reason API appears; `make-app.sh` copies it
  to the app's top-level `Contents/Resources`.
- **Dev builds use a separate identity**: `DEV=1` (what `make launch` runs)
  appends `.dev` to the bundle ID and " Dev" to the display name. TCC grants,
  UserDefaults and the sandbox container are keyed by bundle ID, so the dev
  build keeps its own grants instead of invalidating the shipping build's (and
  vice versa). `DEV=1` and `MAS=1` are mutually exclusive.
- `make mas` signs with Apple Distribution and emits a `.pkg` for Transporter;
  it refuses to run unless App Sandbox is enabled. A normal App Store
  submission does not need a provisioning profile — App Sandbox entitlements
  are unrestricted — but TestFlight does; pass `PROVISION_PROFILE=...` to embed
  one. Notarization is only for Developer ID distribution, not the App Store.
- TCC grants are keyed to the signing identity, so switching between Developer
  ID, Apple Distribution (`make mas`) and ad-hoc resets them. Test on a clean
  account with `tccutil reset ScreenCapture <bundleID>` (or the matching
  service) after re-signing.

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
- Ad-hoc re-signing changes the code identity macOS associates with TCC
  decisions, so a rebuild may re-prompt for protected-folder access even if it
  was already granted. `make app` prefers Developer ID, whose grants survive
  rebuilds; `make launch` uses the separate `.dev` identity. Do not work around
  a TCC prompt by disabling checks.
- With `--arch arm64 --arch x86_64`, SwiftPM puts products in
  `.build/apple/Products/Release`, not `.build/release`. Ask
  `swift build … --show-bin-path` instead of hardcoding the path.
- Rebuilding while an instance is running replaces the executable on disk;
  macOS can then kill that instance with `SIGKILL (Code Signature Invalid)`
  when it next faults in the changed code pages (often during quit). That is
  not an app crash — quit the running app before `make app` / `swift run`.
  The evidence is in `~/Library/Logs/DiagnosticReports/`; the app's own log
  ends without a crash entry because the kernel kills the process outright.
- Standard AppKit menus only localize when the app bundle declares
  `CFBundleLocalizations`; `Scripts/make-app.sh` writes it. If the app uses
  TCC-protected folders, add the matching usage descriptions to the Info.plist
  heredoc and localized copies under
  `Contents/Resources/<lang>.lproj/InfoPlist.strings`.
- UserDefaults live under the bundle ID, so state saved during `swift run`
  does not carry over to the .app (different domain), and the `.dev` build does
  not share state with the shipping build either.
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

Forks should keep `TEMPLATE.md` up to date and use
`make template-diff SOURCE=/path/to/swiftui-starter` to see changes in the
template-managed files (`Makefile`, `Scripts/`, `docs/ui-testing.md`, the
privacy manifest). The diff is read-only; merge app-specific customizations by
hand instead of overwriting the whole file.

## Layout: sidebar under the titlebar

The main window uses `fullSizeContentView` with a transparent titlebar, so the
sidebar's native translucent material reaches the traffic lights. Keep these
coordinated:

- `TitlebarFlattener` sets `fullSizeContentView` and
  `titlebarAppearsTransparent` on the window. Do not add an opaque toolbar
  background on top of it.
- `SidebarView` ignores the top safe area and reserves the traffic-light strip
  in its header padding. `NavigationSplitView` would otherwise add its own top
  inset on top of the titlebar safe area, doubling the spacing.
- `ContentView` hides the window toolbar background and overlays the page color
  on the detail column at the root's top safe-area inset, so scrolled content
  does not show through the toolbar controls.
- Never paint an opaque background over the sidebar — the translucent material
  is the design. Panels that start below the toolbar must not ignore the top
  safe area.
