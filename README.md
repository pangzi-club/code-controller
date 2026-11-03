# CodeViewer

[English](README.md) | [中文](README.ZH.md)

A SwiftUI + SwiftPM template for macOS 14+ desktop apps, demonstrated by a
simple file browser — no Xcode project needed. The package splits into a
library (all app code) and a thin `@main` executable, so Xcode Previews work
out of the box.

## Features

- **Workspaces sidebar**: add folders from the workspace menu or by dragging them in; each gets a stable color tile derived from its path. The sidebar hosts a Files/Graph pane switch, uses the native translucent material, and extends under the transparent titlebar to the traffic lights.
- **File tree**: lazily loaded recursive tree (directories first, then by name) with hover highlighting, context menus (Open, Show Git Diff, Show in Finder) and per-row git status badges.
- **Document tabs**: one tab per file with middle-truncating titles, two-row wrapping, a close button and the same git status badge. ⌘W closes the selected tab (does nothing with no tabs open, so it never takes the window down); ⌘1…⌘9 switch tabs. Views are pooled in an LRU (8 entries) so switching tabs preserves scroll position and selection.
- **Syntax highlighting**: highlight.js (via HighlighterSwift) running on a background actor, with a `SyntaxHighlighter` protocol seam for future engines. Finished results cache per document version and theme (LRU, 12 entries); the styled output is re-pinned to the fixed mono font and line height so the line-number ruler never shifts; colors follow the system light/dark appearance.
- **Git integration**: repository detection at the workspace root with graceful degradation when git is missing; `git status` badges (M/A/D/?) on tree rows and tabs; read-only diff sheets for files (working tree vs HEAD) and whole commits (⌘R refreshes tree, statuses, commits and the selected document).
- **Commit history**: a Graph pane in the sidebar listing recent commits — subject, author, relative date, branch badge — click one to open its full diff.
- **Live refresh**: FSEvents watch per workspace with debounced bursts; the tree, git statuses and changed open documents refresh automatically. Unchanged documents are skipped via mtime/size checks so highlight caches survive unrelated churn.
- **Settings window**: system/light/dark theme picker and an interface language picker (system/English/简体中文), persisted and applied app-wide — a separate fixed-size window opened with ⌘, from the App menu.
- **Persistence**: the workspace list is stored as security-scoped bookmarks in UserDefaults (so the sandboxed App Store build keeps access across relaunches; stale folders are dropped), and the system restores the window frame across relaunches.
- **Localization**: English and Simplified Chinese, following the system language by default with an override in Settings (takes effect on relaunch).
- **Diagnostics**: structured unified logging mirrored to a rotating file log, with a launch banner that records the bundle, sandbox and log paths.
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
run), `make test`, `make check-l10n` (verify localization key parity),
`make app` (assemble the universal bundle), `make install` (assemble the
universal bundle and replace the copy in /Applications), `make launch`
(assemble and open the dev build), `make mas` (App Store package), `make build`,
`make rename` (template rename), `make template-diff` (show template drift),
`make clean`.
Run `make help` to list them. `.vscode/launch.json` provides Debug/Release
launch targets for the VS Code Swift extension; `rename.sh` updates them.

## Verifying the UI

Unit tests cover pure logic. Window frame restoration, the settings window,
focus rings, empty states, dark mode and localization only exist in the
assembled app — always verify them on `make app` output, not the bare
`swift run` binary. `docs/ui-testing.md` is the AX + `screencapture` + CGEvent
playbook, including the helper sources and the per-change checklist.

## Diagnostics

`Log` writes to unified logging (subsystem = bundle ID) and mirrors every line
to `~/Library/Logs/<display name>/app.log`, rotated to `app.log.1` when it
exceeds 2 MB at launch. The App Store build keeps the same path inside its
sandbox container (`~/Library/Containers/<bundleID>/Data/Library/Logs/...`).
`Log.bootstrap()` records the bundle, sandbox and log paths before the first
window appears. Stream live with:

```sh
/usr/bin/log stream --predicate 'subsystem == "<bundleID>"' --level debug
```

## Xcode Previews

Open `Package.swift` in Xcode (it synthesizes the schemes; `.swiftpm/` is
gitignored). The package has two targets: the **CodeViewer** library with
all views, models and stores, and the **CodeViewerApp** executable that only
holds the `@main` entry point. Previews need a library product — a
command-line-tool target cannot power the canvas — so the views (each file
ends in a `#Preview` block) preview against the library scheme. Types used by
the executable target must be `public`. Previews that need files use
`PreviewFixtures`, which builds a sample folder under the temporary directory
instead of pointing at a developer's home path.

## Using This as a Template

To start a new app from this repository, rename everything in one shot:

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

This renames the package and targets in `Package.swift`, moves `Sources/` and
`Tests/` (the executable target becomes `MyAppApp`), renames the `@main`
struct, and updates the identity in `AppInfo.swift` (the bundle ID defaults to
`com.example.<NewName>` when omitted), the READMEs, `AGENTS.md` and `docs/`.
It finishes by listing any file that still contains the old name, so configs
or scripts added later are visible instead of silently stale. The display
name can then be tuned freely in `AppInfo.swift` — it may contain spaces.
`AGENTS.md` also documents the conventions and known gotchas of this codebase.

`TEMPLATE.md` records the template version and the files that follow upstream.
In a fork, run `make template-diff SOURCE=/path/to/swiftui-starter` to see the
drift; the script is read-only, so app-specific additions can be merged by
hand.

## Packaging as a .app

For the proper experience (Dock icon, menu bar, Cmd+Tab, double-clickable in
Finder), assemble a universal app bundle:

```bash
make app                    # build/CodeViewer.app (arm64 + x86_64)
make launch                 # build/CodeViewer-Dev-<host arch>.app, opened
make install                # universal build, then replace /Applications/CodeViewer.app
```

`make-app.sh` builds a release bundle for the requested architectures: by
default `make app` lipo-merges arm64 and x86_64 into one universal
`build/<Display Name>.app`, so the same bundle runs natively on Apple Silicon
and Intel Macs. Set `ARCHS` to override, e.g. `ARCHS=arm64 make app` for a thin
host-arch bundle, or `ARCHS="arm64 x86_64" make app` for one bundle per
architecture (`build/<Display Name>-<arch>.app`). Each bundle gets
the generated app icon (`Scripts/make-icon.swift` draws it programmatically),
an Info.plist written from `AppInfo.swift` (display name, bundle ID, marketing
version and build number) and `Package.swift` (minimum macOS), and a copy of
the privacy manifest. `make app` signs the bundle with
`Scripts/App.entitlements` and uses a Developer ID certificate when the keychain
has one (ad-hoc fallback); `SIGN_IDENTITY` overrides the choice. Local and
Developer ID builds are **not sandboxed** by default — add local or
hardened-runtime entitlements to that file when needed.

The App Store build is sandboxed, so the demo persists app-scoped security
bookmarks for its folders instead of plain paths — a path alone loses access
after relaunch. The sandbox moves Application Support, UserDefaults and caches
into `~/Library/Containers/<bundleID>/Data`, so folders and preferences saved
during `swift run` or `make app` do not carry over to the App Store build.
`CFBundleLocalizations` is declared in the generated `Info.plist` so the
standard AppKit menus follow the in-app language.

`make launch` builds a separate dev identity for the host architecture: the
bundle ID gets a `.dev` suffix and the display name a `-Dev` suffix. TCC grants
and UserDefaults are keyed by bundle ID (and, when sandboxed, the container), so
rebuilding the dev app does not invalidate the shipping app's permissions (and
vice versa).

### App Store

```bash
make mas                    # build/CodeViewer-0.1-1.pkg
```

`make mas` signs with Apple Distribution and writes a `.pkg` for Transporter.
The package contains a single universal (arm64 + x86_64) sandboxed bundle. It
signs with `Scripts/App.sandbox.entitlements` and refuses to run unless App
Sandbox is enabled there. Bump `AppInfo.build` for every upload
(`CFBundleVersion`); `CFBundleShortVersionString` comes from `AppInfo.version`.
A normal App Store submission does not need a provisioning profile, but
TestFlight does — pass `PROVISION_PROFILE=...` to embed one. Notarization is
only for Developer ID distribution. `INSTALLER_IDENTITY` overrides the
installer certificate.

If the app reads TCC-protected folders (Downloads, Desktop, Documents, camera,
microphone, …), add the matching `NS*UsageDescription` keys to the Info.plist
heredoc in `Scripts/make-app.sh`, plus localized copies in
`Contents/Resources/<lang>.lproj/InfoPlist.strings`, so the system prompt
follows the user's language.

## Project Layout

```
Sources/
├── CodeViewer/                 # Library target: all views, models, stores
│   ├── AppInfo.swift             # Display name / bundle ID / version / build (single source of truth)
│   ├── ContentView.swift         # Split layout, detail pane, tab key monitor
│   ├── SidebarView.swift         # Workspace menu + Files/Graph pane switch
│   ├── FileTree.swift            # Lazily loaded tree store
│   ├── FileTreeView.swift        # Tree rows with git badges
│   ├── DocumentTab.swift         # Tab model (URL + per-tab DocumentStore)
│   ├── DocumentTabBar.swift      # Wrapping tab strip with badges
│   ├── CodePane.swift            # LRU-pooled NSTextView editors + pinned metrics
│   ├── SyntaxHighlighting.swift  # SyntaxHighlighter protocol, HighlighterSwift adapter, cache
│   ├── GitService.swift          # git CLI: status/diff/log + observable status store
│   ├── GitGraphView.swift        # Commit history pane
│   ├── GitDiffSheet.swift        # Read-only diff sheet (file or commit)
│   ├── WorkspaceWatcher.swift    # FSEvents watcher with debounce
│   ├── WorkspaceSession.swift    # Per-workspace tabs, tree, git, watcher
│   ├── Log.swift                 # Unified logging + rotating file log
│   ├── PreviewFixtures.swift     # DEBUG-only sample folder for Xcode Previews
│   ├── L10n.swift                # Localization helpers
│   ├── SettingsStore.swift       # Theme + language preferences and persistence
│   ├── SettingsView.swift        # Settings window content (theme + language pickers)
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       ├── zh-Hans.lproj/Localizable.strings
│       └── PrivacyInfo.xcprivacy  # Required-reason API declarations
└── CodeViewerApp/
    └── CodeViewerApp.swift     # Thin @main entry point, window scene, ⌘R/⌘S commands
Tests/CodeViewerTests/          # Swift Testing suite
Scripts/
├── App.entitlements              # Local/Developer ID entitlements (unsandboxed)
├── App.sandbox.entitlements      # App Store: sandbox + user-selected files + bookmarks
├── check-l10n.py                 # Localization key parity check
├── make-app.sh                   # Per-architecture release builds + .app/.pkg assembly
├── make-icon.swift               # Programmatic app icon generator
├── rename.sh                     # One-shot template rename
└── template-diff.sh              # Read-only drift check against a starter checkout
docs/
└── ui-testing.md                 # AX + screencapture + CGEvent verification playbook
TEMPLATE.md                       # Template version, managed files and merge rules
AGENTS.md                         # Conventions and gotchas for humans and agents
.vscode/launch.json               # Debug/Release targets for the VS Code Swift extension
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against the Settings override (if one is stored) and
`Locale.preferredLanguages`, and loads the matching `en` or `zh-Hans` `.lproj`
bundle explicitly — the multi-localization module bundle would follow the
system language and ignore the override. The language is fixed at launch —
strings are baked into views when they are built — so a changed setting asks
to be relaunched before it applies. Run `make check-l10n` after adding strings
to catch missing or duplicate keys; `swift test` also checks empty values and
every enum label key.
