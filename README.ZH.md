# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

一个基于 AppKit 和 SwiftPM 的 macOS 桌面应用模板，以一个简单的文件浏览器作为示例 —— 无需 Xcode 工程文件，也没有 nib，所有窗口、菜单和视图全部用代码构建。包内拆分为 library（全部应用代码）和只含 `@main` 的薄 executable，测试 target 因此可以通过 `@testable` 导入全部代码。

## 功能

- **侧边栏**：文件夹列表，圆角强调色选中与悬停高亮；通过「添加文件夹」按钮、File 菜单（⌘N）或直接拖拽添加；右键可移除或在 Finder 中显示。每个文件夹根据路径分配一个稳定的彩色标识块。
- **文件列表**：卡片式展示所选文件夹的直接子项（文件夹在前，再按名称排序），带系统图标、文件大小和修改时间。双击用系统默认应用打开；右键菜单提供「打开」和「在 Finder 中显示」；行悬停高亮，行间有缩进分隔线。
- **设置页**：系统 / 浅色 / 深色主题切换，选择会被持久化并通过 `NSApp.appearance` 应用到全局。可从侧边栏齿轮或菜单 ⌘, 进入。
- **菜单栏与工具栏**：菜单栏由 `AppDelegate` 用代码构建 —— 关于、设置、隐藏、退出，以及 File / Edit / View / Window 菜单（切换侧边栏为 ⌥⌘S）。窗口使用统一工具栏，含侧栏开关，文件夹名作为内嵌标题；无需 MainMenu.xib。
- **持久化**：文件夹列表存于 UserDefaults（失效路径会被自动过滤），窗口位置和大小跨启动保留。
- **本地化**：支持英文和简体中文，自动跟随系统语言 —— 包括所有菜单标题。
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

## Library / Executable 拆分

包内有两个 target：**DemoExplorer** library 包含全部窗口控制器、视图控制器、模型和 store；**DemoExplorerApp** executable 只保留 `@main` 入口。这样拆分让测试 target 能 `@testable import DemoExplorer` 导入应用代码，也保持了 `Scripts/rename.sh` 依赖的 `Sources/<Library>` + `Sources/<Library>App` 目录结构。executable 只会用到 `AppDelegate` 一个类型，因此它也是唯一的 `public` 类型。

## 作为模板使用

基于本仓库开发新应用时，一条命令完成整体重命名：

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

脚本会重命名 `Package.swift` 中的包和 target、移动 `Sources/` 与 `Tests/` 目录（executable target 会变成 `MyAppApp`）、重命名 `@main` 入口，并更新 `AppInfo.swift` 中的身份信息（未指定 bundle ID 时默认 `com.example.<NewName>`）、README 和 `AGENTS.md`。显示名之后可以在 `AppInfo.swift` 里随意调整（允许包含空格）。代码库的约定和已知坑都记录在 `AGENTS.md` 中。

## 打包成 .app

想要完整体验（Dock 图标、菜单栏、Cmd+Tab、可在 Finder 中双击打开），需要组装应用包：

```bash
./Scripts/make-app.sh          # 产物：build/DemoExplorer.app
open build/DemoExplorer.app
```

脚本会构建 release 二进制、生成应用图标（`Scripts/make-icon.swift` 程序化绘制）并做 ad-hoc 签名。应用身份统一定义在 `Sources/DemoExplorer/AppInfo.swift`：脚本从它读取显示名、bundle ID 和版本，target/二进制名则从 `Package.swift` 派生，没有任何重复定义。`.app` 的偏好设置存储在 bundle ID 名下，`swift run` 期间保存的文件夹不会自动带过去。

## 项目结构

```
Sources/
├── DemoExplorer/                  # Library target：全部应用代码
│   ├── AppInfo.swift              # 显示名 / bundle ID / 版本（唯一事实来源）
│   ├── AppDelegate.swift          # NSApplicationDelegate：菜单栏、主题、启动
│   ├── ContextMenuTableView.swift # 支持行右键菜单的 NSTableView 子类
│   ├── FileListViewController.swift # 卡片式文件列表
│   ├── FolderStore.swift          # 侧边栏文件夹列表 + 持久化
│   ├── L10n.swift                 # 本地化辅助
│   ├── MainWindowController.swift # 主窗口、分栏、详情页、窗口位置持久化
│   ├── Models.swift               # 文件加载、打开/定位助手、文件夹选择器
│   ├── SettingsStore.swift        # 主题偏好 + 持久化
│   ├── SettingsViewController.swift # 设置页（主题切换）
│   ├── SidebarViewController.swift  # 侧边栏表格、拖放、文件夹配色
│   ├── StyleSupport.swift           # 背景/阴影/徽章/虚线按钮辅助
│   ├── WindowFramePersistence.swift # 窗口位置手动保存/恢复（纯逻辑有测试）
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── zh-Hans.lproj/Localizable.strings
└── DemoExplorerApp/
    └── DemoExplorerApp.swift      # 薄 @main 入口
Tests/DemoExplorerTests/           # Swift Testing 测试
Scripts/
├── make-app.sh                    # release 构建 + .app 包组装
├── make-icon.swift                # 应用图标程序化生成
└── rename.sh                      # 一键模板重命名
AGENTS.md                          # 面向人和 agent 的约定与坑位说明
```

## 本地化说明

SwiftPM 构建时会把资源包里的 `.lproj` 目录名转成小写，而 `Bundle` 的资源名查找是大小写敏感的，导致系统语言偏好 `zh-Hans` 无法匹配到 `zh-hans.lproj`。`L10n` 自行根据 `Locale.preferredLanguages` 判断语言并显式加载对应的 `.lproj` 包来绕过这个问题。
