# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

CodeCtrl, a native macOS code viewer — workspaces, a file tree, document
tabs with syntax highlighting, git status badges, changed-line tints and
inline commit diffs — built with SwiftUI and SwiftPM only; there is no
`.xcodeproj`. Files open read-only. Targets macOS 14+ with Swift tools 5.9.
The repository started from a SwiftUI + SwiftPM starter and keeps its
tooling (`Scripts/rename.sh`, `TEMPLATE.md`).

The package has two targets: a **library** (`CodeViewer`, all the views,
models, stores and helpers) and a thin **executable** (`CodeViewerApp`, just
the `@main` entry point). Splitting them lets Xcode Previews work — open
`Package.swift` in Xcode and preview with the library scheme; previews require
a library product, not a command-line tool. Previews that need sample file
system data use `PreviewFixtures` (DEBUG-only, under the temporary directory)
instead of a developer's home path.

## Commands

`make help` lists everything. The ones that matter:

- `make dev` — debug build and run (`swift run`)
- `make test` — run the test suite (`swift test`)
- `make check-l10n` — verify both `Localizable.strings` files have the same keys
- `make build` — release build
- `make app` — assemble the universal `build/<Display Name>.app`
  (unsandboxed, Developer ID when the keychain has one, otherwise ad-hoc);
  `ARCHS` overrides, e.g. `ARCHS=arm64 make app` for a thin host bundle or
  `ARCHS="arm64 x86_64" make app` for one bundle per architecture
  (`build/<Display Name>-<arch>.app`)
- `make install` — assemble the universal bundle (`ARCHS=universal`, a single
  lipo-merged `build/<Display Name>.app`), then replace
  `/Applications/<Display Name>.app` with it; quit the running copy first (see
  the code-signature `SIGKILL` gotcha below)
- `make mas` — assemble the sandboxed universal App Store build and
  `build/<Display Name>-<version>-<build>.pkg` (Apple Distribution;
  `PROVISION_PROFILE` embeds a TestFlight profile)
- `make launch` — assemble and open `build/<Display Name>-Dev-<arch>.app` for
  the host architecture, with bundle ID `<bundleID>.dev` and its own TCC grants
  and UserDefaults
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
  in `Tests/CodeViewerTests/`. Add tests for new logic in `Models.swift`,
  stores, and helpers; views don't need snapshot tests in this template.
  Suites that share a UserDefaults key are `@Suite(.serialized)` — keep that
  when adding UserDefaults-touching tests, Swift Testing runs in parallel.
  File-system tests build their fixtures under
  `FileManager.temporaryDirectory`; never touch the real home directory.
  `LocalizationTests` also checks key parity, empty values and every enum
  label key, so a new label that is not in both catalogs fails `swift test`.
- **State** lives in `ObservableObject` stores (`SettingsStore`, `FolderStore`)
  persisted to UserDefaults and injected via `.environmentObject`. The folder
  list stores app-scoped security bookmarks under `folderBookmarks` (not plain
  paths), so the sandboxed App Store build keeps access across relaunch;
  `FolderStore` starts each scope on launch and stops it when the folder is
  removed. Local builds are unsandboxed but resolve the same bookmarks. Window
  geometry is owned by SwiftUI/NSWindow restoration:
  `.defaultSize(1080×720)` and `.defaultPosition(.center)` apply on first
  launch, and the system restores the frame on later launches. Do not add a
  second frame store in UserDefaults.
- **Settings is a separate window**, not a page inside the main window: a
  standard SwiftUI `Settings` scene (singleton, fixed to its content size,
  centered, opened from the App menu with ⌘,). The App menu is the single
  entry point; do not add an in-window settings button. The scene opens only
  on demand and is not restored at launch. `openSettings` is available on
  macOS 14 if a fork adds a programmatic opener. The standard menu item and
  window title follow the system language, not the in-app language override.
- **Access control**: the library target (`Sources/CodeViewer/`) must mark
  types and members `public` when the executable target
  (`Sources/CodeViewerApp/`) uses them. Protocol requirements (`body`, …) on
  public types must also be `public`.

## Sandbox and distribution

- Local and Developer ID builds (`make app`, `make launch`, `swift run`) are
  **not sandboxed**. `make app` signs with `Scripts/App.entitlements`, which is
  empty by default; add local or hardened-runtime entitlements there.
- The App Store build (`make mas`) signs with
  `Scripts/App.sandbox.entitlements`: App Sandbox, user-selected read-write
  and app-scoped bookmarks. The script refuses to package without App Sandbox.
  Add an entitlement only when a feature requires one — App Review sees all
  of them.
- The sandbox (MAS build only) moves Application Support, Caches, Logs and
  UserDefaults into `~/Library/Containers/<bundleID>/Data`; user-selected
  files stay where they are. Test sandbox behavior with the `make mas` build:
  `make app`, `make launch` and `swift run` read normal paths and will happily
  access files the App Store build rejects.
- `AppInfo.build` is the App Store build number: bump it for every upload
  (`CFBundleVersion`); `CFBundleShortVersionString` comes from `version`.
  `LSMinimumSystemVersion` is parsed from `Package.swift`.
- `Sources/*/Resources/PrivacyInfo.xcprivacy` declares the required-reason APIs
  (UserDefaults `CA92.1`; file timestamps `DDA9.1` / `3B52.1` / `C617.1`).
  Update it whenever a new required-reason API appears; `make-app.sh` copies it
  to the app's top-level `Contents/Resources`.
- **Dev builds use a separate identity**: `DEV=1` (what `make launch` runs)
  appends `.dev` to the bundle ID and `-Dev` to the display name. TCC grants
  and UserDefaults are keyed by bundle ID (and the sandbox container, when
  sandboxed), so the dev build keeps its own state instead of colliding with
  the shipping build. `DEV=1` and `MAS=1` are mutually exclusive.
- `make mas` signs with Apple Distribution and emits a `.pkg` for Transporter.
  A normal App Store submission does not need a provisioning profile — App
  Sandbox entitlements are unrestricted — but TestFlight does; pass
  `PROVISION_PROFILE=...` to embed one. Notarization is only for Developer ID
  distribution, not the App Store.
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
- The **NavigationSplitView sidebar toggle** is replaced: hide the system
  control with `.toolbar(removing: .sidebarToggle)` and provide a custom
  toolbar button with `.focusEffectDisabled()`. The system toggle keeps a
  focus ring that SwiftUI cannot clear; the custom button must not introduce
  a new one. Apply the removal to the sidebar column's content — placing it
  on the split view or the detail column leaves the system toggle visible.
- A horizontal SwiftUI `ScrollView` is not vertically inert: on macOS 27
  SwiftUI sized the tab strip's document view 52pt taller than its 46pt clip
  view (the titlebar's safe area leaked into it), so a vertical two-finger
  scroll pushed the tabs out of the strip and left them there.
  `DocumentTabBar` wraps its content in `TabVerticalScrollLock`, which pins
  the clip view to y = 0 and sets `verticalScrollElasticity = .none`. Do not
  remove it; horizontal scrolling and `ScrollViewReader.scrollTo` still work.
- The code pane's line-number ruler assumes one fixed line height:
  `CodeTextFactory.paragraphStyle` pins `EditorFont.pinnedLineHeight`
  (`defaultLineHeight + 2`, rounded) through `minimumLineHeight` /
  `maximumLineHeight`, and `EditorFont.lineHeight` is the height TextKit
  *actually* lays a line out at with that pin — measured once per font, not
  derived, because fonts with fractional leading (Monaco at 12pt reports
  16.002) come out a point taller than the metric and every ruler number then
  drifts a point per line. The ruler derives visible lines from the scroll
  offset instead of querying TextKit layout. Both values come from the
  settings' editor font (an `NSLayoutManager` query — main thread only, so
  every restyling path runs on the main actor). When the user changes font
  family or size, `CodeEditorView.applyFont` re-pins the paragraph style and
  the ruler together, and the `HighlightCache` key includes the font id.
  `CodeEditorView` pins the ruler as a separate view to the scroll view's
  leading edge; do not attach it as an `NSRulerView` overlay. The code clip
  view therefore keeps a zero minimum scroll origin, and the two views cannot
  draw into the tab bar above them.
- Working-tree line marks (`LineChangeMap`) are painted as `.backgroundColor`
  attributes on the editor's text storage after the paint, never inside the
  attributed string the highlighter produced: `CodeTextFactory.styled` strips
  backgrounds, so the tints are the only ones in the storage and
  `setLineChanges` can clear them wholesale before repainting. Backgrounds do
  not affect metrics, so the ruler contract above still holds. Line numbers
  come from `git diff HEAD --unified=0` (staged and unstaged both count); git
  reports an empty new-side range as the line *before* a removal, so a removed
  block's seam is `newStart + 1`. Untracked files are whole-file additions
  rather than diffs, and so are files inside an untracked directory (git
  status collapses such a directory to one row, so they carry no status of
  their own). `GitStatusStore.refreshLineChanges` rebuilds the marks for every
  open file tab on each status refresh, so a closed, reverted or staged-clean
  tab drops its tint instead of keeping a stale one.
- `make-app.sh` must copy **every** SwiftPM resource bundle from the products
  directory into `Contents/Resources` — the library's own and one per
  dependency (`Highlighter_Highlighter` for the syntax highlighter). A
  dependency's `Bundle.module` fatals on first use in the assembled app when
  its bundle is missing, and unit tests never catch it because they run from
  `.build`, where the bundle is reachable.
- Syntax highlighting is `SyntaxHighlighter` (protocol) over
  `HighlighterSwift` — note the module/product name is `Highlighter`, not the
  repository name — owned by a background actor (`HighlightrHighlighter`
  style: one engine per actor, theme loads serialized). `CodeTextFactory.
  styled` must re-pin font and paragraph style over any highlighter output
  (colors may be themed, metrics may not — the ruler contract above).
  Finished results cache per document version + theme + editor font in
  `HighlightCache`; every editor theme renders on its own background color
  (parsed from the theme CSS), and `SettingsStore` keeps one theme per
  interface appearance (`lightTheme` / `darkTheme`, resolved by
  `resolvedHighlightTheme(for:)`). `DocumentStore.reloadIfChanged`
  (mtime + size) is what keeps watcher bursts from invalidating that cache,
  so do not replace plain `reload()` with it on the watcher path.
- `git log --pretty=format:` interleaves a bare newline **between** records
  (separator semantics, unlike `tformat:`), so every parsed commit record
  after the first starts with `\n`; strip it or the hash is polluted and
  `git show` exits 128. Repository detection checks only the workspace root
  for `.git` — deliberately no walk-up, so a workspace that is a subfolder of
  some enclosing repository stays badge-free instead of showing statuses
  from a repo the user never chose.
- The tab key monitor (`ContentView.installTabKeyMonitor`) matches keys by
  ANSI keycode with only ⇧⌃⌥ rejected as modifiers. Caps lock stamps
  `.alphaShift` on real key events and uppercases the event characters, so
  strict flags equality or matching the literal `"w"` misses
  a physical ⌘W and the system Close shortcut closes the whole window.
  CGEvent injection does not reproduce this — it carries no `.alphaShift`.
- SwiftUI window restoration keys the saved frame by the scene's explicit id,
  or by its content type when no id is given: the main `Window("", id: "main")`
  saves as `NSWindow Frame main` in the app's UserDefaults (the old
  `WindowGroup(id:)` scene keyed by content type, whose mangled name could
  contain a per-launch runtime address). Keep every top-level scene wrapper
  non-private: a private type mangles to a name containing a runtime address,
  so the autosave key changes every launch and the frame is never restored.
  Changing the scene type or id also abandons the saved frame once.
- On macOS 14/15 the default `applicationShouldHandleReopen` handling re-shows
  a closed window on its own, and `openWindow(id:)` on a `WindowGroup` always
  creates a *new* instance — combining them produced two windows per Dock
  click. The main scene is therefore a `Window("", id: "main")`, a single
  unique instance: the system restore and the environment's `openWindow`
  action both resolve to the same window, so the race is structural, not
  timing-based. The `AppDelegate` adaptor in `CodeViewerApp.swift` returns
  `true` to let the system restore, and only after a 0.6 s single-flight delay
  (which absorbs the second event of a double click) calls `openWindow` when
  no visible main window exists — that fallback only fires on older systems.
  The root view hands `openWindow` to the delegate from `.onAppear`, because
  the action is reachable only from inside a scene. A fork that genuinely
  needs multiple windows must instead reuse an existing window in the reopen
  handler (`makeKeyAndOrderFront`) and never create one; do not go back to
  `WindowGroup` for the main scene.
- Test frame restoration on the assembled `.app` (`make launch` / `make app`).
  An unbundled `swift run` binary has no bundle identity for system
  restoration, so it does not provide a meaningful frame-persistence check.
- SwiftUI `@FocusState` does not move first responder into a toolbar
  `TextField` on macOS. Wrap an `NSSearchField` in an `NSViewRepresentable`
  and call `makeFirstResponder` whenever its focus token changes; have the
  ⌘F menu item post a notification that bumps that token.
- Ad-hoc re-signing changes the code identity macOS associates with TCC
  decisions, so a rebuild may re-prompt for protected-folder access even if it
  was already granted. `make app` prefers Developer ID, whose grants survive
  rebuilds; `make launch` uses the separate `.dev` identity. Do not work around
  a TCC prompt by disabling checks.
- With `--arch`, SwiftPM puts products outside `.build/release` in a
  toolchain-specific products directory (older toolchains use
  `.build/apple/Products/Release`). Ask `swift build … --show-bin-path` instead
  of hardcoding the path. Single-arch builds can reuse one output directory, so
  `make-app.sh` packages each architecture before starting the next build.
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
READMEs, `AGENTS.md`, `docs/` and `.vscode/launch.json`. It finishes by listing
any file that still contains the old name, so configs or scripts added later
are visible instead of silently stale. The Makefile and `make-app.sh` discover
`AppInfo.swift` via `Sources/*/AppInfo.swift`, so they keep working across
renames. The bundle ID defaults to `com.example.<NewName>` when omitted.

Forks should keep `TEMPLATE.md` up to date and use
`make template-diff SOURCE=/path/to/swiftui-starter` to see changes in the
template-managed files (`Makefile`, `Scripts/`, `docs/ui-testing.md`, the
privacy manifest). The diff is read-only; merge app-specific customizations by
hand instead of overwriting the whole file.

## Layout: sidebar under the titlebar

The main window uses `.windowStyle(.hiddenTitleBar)`, so content extends under
the titlebar and the sidebar's native translucent material reaches the traffic
lights. Keep these coordinated:

- `hiddenTitleBar` also suppresses the native window title. `FileListView`
  supplies the folder name as an explicit `ToolbarItem(placement: .navigation)`
  and keeps `.navigationTitle(folder.name)` for the Window menu and
  Accessibility.
- `SidebarView` ignores the top safe area and reserves the traffic-light strip
  with `toolbarStripHeight + 8` header padding in windowed mode. Full screen
  uses 8pt; both headers have a 20pt row height so the sidebar and detail labels
  align. `NavigationSplitView` would otherwise add its own top inset on top of
  the titlebar safe area, doubling the spacing.
- `ContentView` hides the window toolbar background, removes the system sidebar
  toggle, and overlays the page color on the detail column at the root's top
  safe-area inset, so scrolled content does not show through the toolbar
  controls. `WindowChrome` hides the toolbar in full screen by setting
  `NSToolbar.isVisible`, and re-asserts it on `styleMask` observation, view
  updates and `didEnterFullScreen` because AppKit restores it mid-transition.
  Do not swap that for `.toolbar(.hidden, for: .windowToolbar)`: the modifier
  only empties the titlebar, so the detail column keeps the toolbar-height top
  safe area and, before macOS 26, full screen loses the traffic lights from the
  auto-hide overlay. Do not add a replacement toolbar inside the content.
- `hiddenTitleBar` leaves the toolbar without a trailing flexible region:
  keep a `ToolbarItem { Spacer() }` before the `.primaryAction` group, or the
  actions pack next to the title instead of the right edge.
- The toolbar adds 5pt leading / 8pt trailing margins. Extra 8pt leading and
  7pt trailing padding put the visible glyph edges on the list card's 20pt
  content inset; re-measure if the toolbar style changes.
- Never paint an opaque background over the sidebar — the translucent material
  is the design. Panels that start below the toolbar must not ignore the top
  safe area.
