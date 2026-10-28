# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

一个基于 SwiftUI 和 SwiftPM 的 macOS 桌面应用模板，以一个简单的文件浏览器作为示例 —— 无需 Xcode 工程文件。包内拆分为 library（全部应用代码）和只含 `@main` 的薄 executable，因此 Xcode Preview 开箱即用。

## 功能

- **侧边栏**：通过「添加文件夹」按钮或直接拖拽添加文件夹；右键可移除或在 Finder 中显示。每个文件夹根据路径分配一个稳定的彩色标识块。
- **文件列表**：卡片式展示所选文件夹的直接子项（文件夹在前，再按名称排序），带系统图标、文件大小和修改时间，支持悬停高亮。
- **打开文件**：双击用系统默认应用打开；右键菜单提供「打开」和「在 Finder 中显示」。
- **设置窗口**：系统 / 浅色 / 深色主题切换，以及界面语言切换（跟随系统 / English / 简体中文），选择会被持久化并应用到全局——独立固定尺寸窗口，⌘,（App 菜单）或侧边栏齿轮均可打开。
- **持久化**：文件夹列表存于 UserDefaults（失效路径会被自动过滤），窗口位置和大小跨启动保留。
- **本地化**：支持英文和简体中文，默认跟随系统语言，可在设置中覆盖（重启后生效）。
- 自动适配浅色 / 深色外观。

## 运行

快速开发迭代时：

```bash
swift run
```

注意：`swift run` 执行的是裸二进制，Launch Services 会把它当作后台进程 —— 没有 Dock 图标，也没有自己的菜单栏。

运行测试（Swift Testing）：

```bash
swift test    # 或：make test
```

项目还带一个 `Makefile`，提供 npm-scripts 风格的快捷命令：`make dev`（调试运行）、`make test`、`make app`（组装 .app）、`make launch`（组装并打开）、`make build`、`make rename`（模板重命名）、`make clean`。运行 `make help` 查看全部。

## Xcode Preview

用 Xcode 打开 `Package.swift`（scheme 由 Xcode 自动生成；`.swiftpm/` 已被 gitignore）。包内有两个 target：**DemoExplorer** library 包含全部视图、模型和 store；**DemoExplorerApp** executable 只保留 `@main` 入口。Preview 必须依赖 library 产物 —— 命令行工具类型的 target 无法驱动画布 —— 因此各视图文件末尾的 `#Preview` 都走 library scheme。executable target 要用到的类型需要标记 `public`。

## 作为模板使用

基于本仓库开发新应用时，一条命令完成整体重命名：

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

脚本会重命名 `Package.swift` 中的包和 target、移动 `Sources/` 与 `Tests/` 目录（executable target 会变成 `MyAppApp`）、重命名 `@main` 结构体，并更新 `AppInfo.swift` 中的身份信息（未指定 bundle ID 时默认 `com.example.<NewName>`）、README 和 `AGENTS.md`。显示名之后可以在 `AppInfo.swift` 里随意调整（允许包含空格）。代码库的约定和已知坑都记录在 `AGENTS.md` 中。

## 打包成 .app

想要完整体验（Dock 图标、菜单栏、Cmd+Tab、可在 Finder 中双击打开），需要组装应用包：

```bash
./Scripts/make-app.sh          # 产物：build/DemoExplorer.app
open build/DemoExplorer.app
```

脚本会构建 release 二进制、生成应用图标（`Scripts/make-icon.swift` 程序化绘制）并做 ad-hoc 签名。应用身份统一定义在 `Sources/DemoExplorer/AppInfo.swift`：脚本从它读取显示名、bundle ID 和版本，target/二进制名则从 `Package.swift` 派生，没有任何重复定义。`.app` 的偏好设置存储在 bundle ID 名下，`swift run` 期间保存的文件夹不会自动带过去。生成的 `Info.plist` 会声明 `CFBundleLocalizations`，让 AppKit 标准菜单跟随应用内语言。

如果应用需要访问受保护文件夹，请在 `Scripts/make-app.sh` 的 Info.plist heredoc 中加入对应的 `NS*UsageDescription`，并提供 `Contents/Resources/<lang>.lproj/InfoPlist.strings` 本地化副本，让系统授权弹窗跟随用户语言。每次重新构建都会重新做 ad-hoc 签名，而签名身份是 macOS 关联 TCC 授权的依据——之前已允许的权限在重新构建后可能再次询问。

## 项目结构

```
Sources/
├── DemoExplorer/                 # Library target：全部视图、模型、store
│   ├── AppInfo.swift             # 显示名 / bundle ID / 版本（唯一事实来源）
│   ├── ContentView.swift         # 分栏布局：侧边栏 + 详情页
│   ├── FileListView.swift        # 卡片式文件列表
│   ├── FolderStore.swift         # 侧边栏文件夹列表 + 持久化
│   ├── Models.swift              # 文件加载、打开/定位助手、文件夹选择器
│   ├── L10n.swift                # 本地化辅助
│   ├── SettingsStore.swift       # 主题 + 语言偏好与持久化
│   ├── SettingsView.swift        # 设置窗口内容（主题 + 语言切换）
│   ├── WindowFrameAutosaver.swift # 窗口位置手动保存/恢复（纯逻辑有测试）
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── zh-Hans.lproj/Localizable.strings
└── DemoExplorerApp/
    └── DemoExplorerApp.swift     # 薄 @main 入口和窗口场景
Tests/DemoExplorerTests/          # Swift Testing 测试
Scripts/
├── make-app.sh                   # release 构建 + .app 包组装
├── make-icon.swift               # 应用图标程序化生成
└── rename.sh                     # 一键模板重命名
AGENTS.md                         # 面向人和 agent 的约定与坑位说明
```

## 本地化说明

SwiftPM 构建时会把资源包里的 `.lproj` 目录名转成小写，而 `Bundle` 的资源名查找是大小写敏感的，导致系统语言偏好 `zh-Hans` 无法匹配到 `zh-hans.lproj`。`L10n` 自行根据设置中的语言覆盖项（如果有的话）和 `Locale.preferredLanguages` 判断语言，并显式加载对应的 `.lproj` 包来绕过这个问题。界面语言在启动时固定——字符串在视图构建时就已写入——所以修改语言设置后需要重启应用才能生效。
