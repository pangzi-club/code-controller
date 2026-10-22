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

```bash
swift run
```

Or open `Package.swift` in Xcode and press Cmd+R.

## Project Layout

```
Sources/FileBrowser/
├── FileBrowserApp.swift   # App entry point and window scene
├── ContentView.swift      # Split layout, sidebar, placeholder
├── FileListView.swift     # Card-style file list
├── FolderStore.swift      # Sidebar folder list + persistence
├── Models.swift           # File loading, open/reveal helpers, folder picker
├── L10n.swift             # Localization helpers
└── Resources/
    ├── en.lproj/Localizable.strings
    └── zh-Hans.lproj/Localizable.strings
```

## Localization Notes

SwiftPM lowercases `.lproj` directory names in the built resource bundle, and
`Bundle` resource lookup is case-sensitive, so the stock CFBundle matching can
miss `zh-hans.lproj` for a `zh-Hans` user preference. `L10n` resolves the
language against `Locale.preferredLanguages` and loads the matching `.lproj`
bundle explicitly to work around this.
