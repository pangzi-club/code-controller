# DemoExplorer

[English](README.md) | [中文](README.ZH.md)

一个基于 SwiftUI 和 SwiftPM 的 macOS 14+ 桌面应用模板，以一个简单的文件浏览器作为示例 —— 无需 Xcode 工程文件。包内拆分为 library（全部应用代码）和只含 `@main` 的薄 executable，因此 Xcode Preview 开箱即用。

## 功能

- **侧边栏**：通过「添加文件夹」按钮或直接拖拽添加文件夹；右键可移除或在 Finder 中显示。每个文件夹根据路径分配一个稳定的彩色标识块。侧边栏使用系统原生的半透明材质，并延伸到透明标题栏的交通灯下方。
- **文件列表**：卡片式展示所选文件夹的直接子项（文件夹在前，再按名称排序），带系统图标、文件大小和修改时间，支持悬停高亮。
- **打开文件**：双击用系统默认应用打开；右键菜单提供「打开」和「在 Finder 中显示」。
- **设置窗口**：系统 / 浅色 / 深色主题切换，以及界面语言切换（跟随系统 / English / 简体中文），选择会被持久化并应用到全局——独立固定尺寸窗口，通过 App 菜单的 ⌘, 打开。
- **持久化**：文件夹列表以 security-scoped bookmark 的形式存于 UserDefaults（App Store 沙盒构建在重启后仍可访问；失效文件夹会被过滤），窗口框架由系统在重启后恢复。
- **本地化**：支持英文和简体中文，默认跟随系统语言，可在设置中覆盖（重启后生效）。
- **诊断**：结构化统一日志会同步写入轮转文件日志，启动横幅会记录 bundle、沙盒和日志路径。
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

项目还带一个 `Makefile`，提供 npm-scripts 风格的快捷命令：`make dev`（调试运行）、`make test`、`make check-l10n`（校验本地化键对齐）、`make app`（同时组装 arm64 和 x86_64 两种包）、`make install`（组装本机架构的包并替换 /Applications 中的副本）、`make launch`（组装并打开开发版）、`make mas`（App Store 安装包）、`make build`、`make rename`（模板重命名）、`make template-diff`（查看与模板的差异）、`make clean`。运行 `make help` 查看全部。`.vscode/launch.json` 提供 VS Code Swift 扩展的 Debug/Release 启动配置，`rename.sh` 会同步更新目标名。

## 验证 UI

单元测试只覆盖纯逻辑。窗口帧恢复、设置窗口、焦点环、空状态、深色模式和本地化只存在于组装后的应用里 —— 务必用 `make app` 的产物验证，而不是裸 `swift run` 二进制。`docs/ui-testing.md` 是 AX + `screencapture` + CGEvent 的验证手册，包含辅助脚本源码和每次改动的检查清单。

## 诊断

`Log` 会把日志写入统一日志（subsystem = bundle ID），并同步镜像到
`~/Library/Logs/<显示名>/app.log`；启动时若文件超过 2 MB，会轮转为
`app.log.1`。App Store 构建的同一路径位于沙盒容器内
（`~/Library/Containers/<bundleID>/Data/Library/Logs/...`）。`Log.bootstrap()`
会在首个窗口出现前记录 bundle、沙盒和日志路径。实时查看：

```sh
/usr/bin/log stream --predicate 'subsystem == "<bundleID>"' --level debug
```

## Xcode Preview

用 Xcode 打开 `Package.swift`（scheme 由 Xcode 自动生成；`.swiftpm/` 已被 gitignore）。包内有两个 target：**DemoExplorer** library 包含全部视图、模型和 store；**DemoExplorerApp** executable 只保留 `@main` 入口。Preview 必须依赖 library 产物 —— 命令行工具类型的 target 无法驱动画布 —— 因此各视图文件末尾的 `#Preview` 都走 library scheme。executable target 要用到的类型需要标记 `public`。需要文件数据的 Preview 使用 `PreviewFixtures`，它在临时目录里生成示例文件夹，而不是指向开发者本机路径。

## 作为模板使用

基于本仓库开发新应用时，一条命令完成整体重命名：

```bash
./Scripts/rename.sh MyApp com.you.MyApp
```

脚本会重命名 `Package.swift` 中的包和 target、移动 `Sources/` 与 `Tests/` 目录（executable target 会变成 `MyAppApp`）、重命名 `@main` 结构体，并更新 `AppInfo.swift` 中的身份信息（未指定 bundle ID 时默认 `com.example.<NewName>`）、README、`AGENTS.md` 和 `docs/`。脚本结束时会列出仍包含旧名称的文件，避免后续新增的配置或脚本被静默遗漏。显示名之后可以在 `AppInfo.swift` 里随意调整（允许包含空格）。代码库的约定和已知坑都记录在 `AGENTS.md` 中。

`TEMPLATE.md` 记录模板版本和跟随上游的文件清单。在 fork 中运行
`make template-diff SOURCE=/path/to/swiftui-starter` 即可查看差异；脚本只读，应用特有的改动可以手工合并。

## 打包成 .app

想要完整体验（Dock 图标、菜单栏、Cmd+Tab、可在 Finder 中双击打开），需要按架构分别组装应用包：

```bash
make app                    # 产物：build/DemoExplorer-arm64.app + build/DemoExplorer-x86_64.app
make launch                 # 产物：build/DemoExplorer-Dev-<本机架构>.app，并打开
make install                # 构建本机架构，然后替换 /Applications/DemoExplorer.app
```

`make-app.sh` 会为每个架构构建 release 包（默认 arm64 和 x86_64，让 Apple Silicon 和 Intel Mac 都运行原生版本）；可用 `ARCHS` 只构建其中一种，例如 `ARCHS=arm64 ./Scripts/make-app.sh`。每个包都会生成应用图标（`Scripts/make-icon.swift` 程序化绘制）、根据 `AppInfo.swift`（显示名、bundle ID、营销版本、构建号）和 `Package.swift`（最低 macOS 版本）生成 Info.plist，并复制隐私清单。`make app` 会逐个使用 `Scripts/App.entitlements` 签名，优先使用 Developer ID 证书，没有则退回 ad-hoc 签名；可用 `SIGN_IDENTITY` 指定身份。本地和 Developer ID 构建**默认不开启沙盒**，需要本地或 hardened runtime 权限时往该文件里加。

App Store 构建开启 App Sandbox，因此 demo 用 security-scoped bookmark 持久化文件夹，而不是只存路径——仅凭路径在重启后会失去访问权限。沙盒会把 Application Support、UserDefaults 和缓存移入 `~/Library/Containers/<bundleID>/Data`，所以 `swift run` 或 `make app` 期间保存的文件夹和偏好不会带到 App Store 构建。生成的 `Info.plist` 会声明 `CFBundleLocalizations`，让 AppKit 标准菜单跟随应用内语言。

`make launch` 为本机架构构建独立的开发身份：bundle ID 追加 `.dev`，显示名追加 `-Dev`。TCC 授权和 UserDefaults 都以 bundle ID 区分（开启沙盒时还包括容器），因此反复重建开发版不会让正式版的权限失效（反之亦然）。

### App Store

```bash
make mas                    # 产物：build/DemoExplorer-0.1-1.pkg
```

`make mas` 使用 Apple Distribution 签名并生成供 Transporter 使用的 `.pkg`；包内是单个 universal（arm64 + x86_64）沙盒应用。它使用 `Scripts/App.sandbox.entitlements`，如果该文件没有开启 App Sandbox 会直接报错。每次上传前递增 `AppInfo.build`（对应 `CFBundleVersion`）；`CFBundleShortVersionString` 来自 `AppInfo.version`。普通 App Store 提交不需要 provisioning profile，但 TestFlight 需要——传入 `PROVISION_PROFILE=...` 即可嵌入。公证（notarization）只用于 Developer ID 分发，不用于 App Store。`INSTALLER_IDENTITY` 可覆盖安装器证书。

如果应用需要读取受 TCC 保护的文件夹（下载、桌面、文稿、相机、麦克风等），请在 `Scripts/make-app.sh` 的 Info.plist heredoc 中加入对应的 `NS*UsageDescription`，并提供 `Contents/Resources/<lang>.lproj/InfoPlist.strings` 本地化副本，让系统授权弹窗跟随用户语言。

## 项目结构

```
Sources/
├── DemoExplorer/                 # Library target：全部视图、模型、store
│   ├── AppInfo.swift             # 显示名 / bundle ID / 版本 / 构建号（唯一事实来源）
│   ├── ContentView.swift         # 分栏布局：侧边栏 + 详情页
│   ├── FileListView.swift        # 卡片式文件列表
│   ├── FolderStore.swift         # 侧边栏文件夹列表 + security-scoped bookmark
│   ├── Log.swift                 # 统一日志 + 轮转文件日志
│   ├── Models.swift              # 文件加载、打开/定位助手
│   ├── PreviewFixtures.swift     # 仅 DEBUG 的 Xcode Preview 示例文件夹
│   ├── L10n.swift                # 本地化辅助
│   ├── SettingsStore.swift       # 主题 + 语言偏好与持久化
│   ├── SettingsView.swift        # 设置窗口内容（主题 + 语言切换）
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       ├── zh-Hans.lproj/Localizable.strings
│       └── PrivacyInfo.xcprivacy  # required-reason API 声明
└── DemoExplorerApp/
    └── DemoExplorerApp.swift     # 薄 @main 入口和窗口场景
Tests/DemoExplorerTests/          # Swift Testing 测试
Scripts/
├── App.entitlements              # 本地/Developer ID 权限（不沙盒）
├── App.sandbox.entitlements      # App Store：沙盒 + 用户选择文件 + bookmark
├── check-l10n.py                 # 本地化键对齐校验
├── make-app.sh                   # 按架构构建 release + .app/.pkg 组装
├── make-icon.swift               # 应用图标程序化生成
├── rename.sh                     # 一键模板重命名
└── template-diff.sh              # 与 starter 的只读差异检查
docs/
└── ui-testing.md                 # AX + screencapture + CGEvent 验证手册
TEMPLATE.md                       # 模板版本、托管文件与合并规则
AGENTS.md                         # 面向人和 agent 的约定与坑位说明
.vscode/launch.json               # VS Code Swift 扩展的 Debug/Release 启动配置
```

## 本地化说明

SwiftPM 构建时会把资源包里的 `.lproj` 目录名转成小写，而 `Bundle` 的资源名查找是大小写敏感的，导致系统语言偏好 `zh-Hans` 无法匹配到 `zh-hans.lproj`。`L10n` 自行根据设置中的语言覆盖项（如果有的话）和 `Locale.preferredLanguages` 判断语言，并显式加载对应的 `en` 或 `zh-Hans` 的 `.lproj` 包 —— 使用多语言 module bundle 会跟随系统语言，忽略语言覆盖。界面语言在启动时固定 —— 字符串在视图构建时就已写入 —— 所以修改语言设置后需要重启应用才能生效。新增字符串后运行 `make check-l10n`，检查缺失或重复的键；`swift test` 还会检查空值和每个枚举 label 键。
