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

快速开发迭代时：

```bash
swift run
```

注意：`swift run` 执行的是裸二进制，Launch Services 会把它当作后台进程 —— 没有 Dock 图标，也没有自己的菜单栏。

项目还带一个 `Makefile`，提供 npm-scripts 风格的快捷命令：`make dev`（调试运行）、`make app`（组装 .app）、`make launch`（组装并打开）、`make build`、`make clean`。运行 `make help` 查看全部。

## 打包成 .app

想要完整体验（Dock 图标、菜单栏、Cmd+Tab、可在 Finder 中双击打开），需要组装应用包：

```bash
./Scripts/make-app.sh          # 产物：build/FileBrowser.app
open build/FileBrowser.app
```

脚本会构建 release 二进制、生成应用图标（`Scripts/make-icon.swift` 程序化绘制）并做 ad-hoc 签名。应用身份统一定义在 `Sources/FileBrowser/AppInfo.swift`：脚本从它读取显示名、bundle ID 和版本，target/二进制名则从 `Package.swift` 派生，没有任何重复定义。`.app` 的偏好设置存储在 bundle ID 名下，`swift run` 期间保存的文件夹不会自动带过去。

## 项目结构

```
Sources/FileBrowser/
├── FileBrowserApp.swift   # 应用入口和窗口场景
├── AppInfo.swift          # 显示名 / bundle ID / 版本（唯一事实来源）
├── ContentView.swift      # 分栏布局、侧边栏、占位页
├── FileListView.swift     # 卡片式文件列表
├── FolderStore.swift      # 侧边栏文件夹列表 + 持久化
├── Models.swift           # 文件加载、打开/定位助手、文件夹选择器
├── L10n.swift             # 本地化辅助
├── Resources/
│   ├── en.lproj/Localizable.strings
│   └── zh-Hans.lproj/Localizable.strings
Scripts/
├── make-app.sh            # release 构建 + .app 包组装
└── make-icon.swift        # 应用图标程序化生成
```

## 本地化说明

SwiftPM 构建时会把资源包里的 `.lproj` 目录名转成小写，而 `Bundle` 的资源名查找是大小写敏感的，导致系统语言偏好 `zh-Hans` 无法匹配到 `zh-hans.lproj`。`L10n` 自行根据 `Locale.preferredLanguages` 判断语言并显式加载对应的 `.lproj` 包来绕过这个问题。
