# FileBrowser

[English](README.md) | [中文](README.ZH.md)

一个基于 SwiftUI 和 SwiftPM 的简单 macOS 文件浏览器，无需 Xcode 工程文件。

## 功能

- **侧边栏**：通过「添加文件夹」按钮或直接拖拽添加文件夹；右键可移除或在 Finder 中显示。每个文件夹根据路径分配一个稳定的彩色标识块。
- **文件列表**：卡片式展示所选文件夹的直接子项（文件夹在前，再按名称排序），带系统图标、文件大小和修改时间，支持悬停高亮。
- **打开文件**：双击用系统默认应用打开；右键菜单提供「打开」和「在 Finder 中显示」。
- **本地化**：支持英文和简体中文，自动跟随系统语言。
- 启动时自动选中第一个文件夹；文件夹列表持久化到 UserDefaults（失效路径会被自动过滤）。
- 自动适配浅色 / 深色外观。

## 运行

```bash
swift run
```

或用 Xcode 打开 `Package.swift` 后直接 Cmd+R 运行。

## 项目结构

```
Sources/FileBrowser/
├── FileBrowserApp.swift   # 应用入口和窗口场景
├── ContentView.swift      # 分栏布局、侧边栏、占位页
├── FileListView.swift     # 卡片式文件列表
├── FolderStore.swift      # 侧边栏文件夹列表 + 持久化
├── Models.swift           # 文件加载、打开/定位助手、文件夹选择器
├── L10n.swift             # 本地化辅助
└── Resources/
    ├── en.lproj/Localizable.strings
    └── zh-Hans.lproj/Localizable.strings
```

## 本地化说明

SwiftPM 构建时会把资源包里的 `.lproj` 目录名转成小写，而 `Bundle` 的资源名查找是大小写敏感的，导致系统语言偏好 `zh-Hans` 无法匹配到 `zh-hans.lproj`。`L10n` 自行根据 `Locale.preferredLanguages` 判断语言并显式加载对应的 `.lproj` 包来绕过这个问题。
