# 快捷 · QuickKey

一个原生 SwiftUI macOS 快捷键手册：选择软件、展开分类、查看用途，再亲手练习。

A native macOS shortcut reference with hands-on practice. Built with SwiftUI and AppKit, without third-party runtime dependencies.

![软件切换与分类抽屉](docs/images/navigation.png)

## 功能

- **155 个操作**：macOS 55、Finder 39、Safari 29、Chrome 32，附官方来源。
- 顶部软件切换区，下方为分类抽屉；48pt 整行可点，轻弹簧反馈并尊重“减少动态效果”。
- 新增软件通过“更多”菜单扩展，当前软件保持可见。
- 原生滚动条固定占位，长短列表切换不会挤动右侧按键。
- **F1–F12**：覆盖常见键帽功能，同时说明标准 F 键、Fn 设置和新旧键盘差异。
- 18 项原生文本练习按实际文本、剪贴板、选区或格式变化反馈；文件和窗口练习观察真实状态。
- 无法可靠检测的外部界面只显示必要提示，不设置完成打卡。

## 构建与运行

需要 **macOS 14+、Swift 6 工具链**。Xcode 或匹配版本的 Command Line Tools 均可用于构建。

```sh
swift run QuickKey
```

生成可从 Finder 打开的应用：

```sh
./scripts/build-app.sh
open dist/QuickKey.app
```

调试构建使用 `./scripts/build-app.sh --debug`。脚本只构建，不会自动启动。应用包使用本机 ad-hoc 签名，未进行开发者签名和 Apple 公证。

## 检查

```sh
./scripts/check-core.sh
./scripts/check-publication.py
```

有完整 Xcode 时运行 `swift test`。只有 Command Line Tools 的环境可能缺少 XCTest，核心检查入口不依赖它。

有交互式桌面时，还可以运行：

```sh
dist/QuickKey.app/Contents/MacOS/QuickKey --integration-test
```

该入口验证真实文本、文件、窗口与固定滚动条几何，不启动 Finder/浏览器，不发送模拟按键。剪贴板检查结束后会恢复原有的可读取内容。检查生成的样例目录会保留。

CI 在 macOS 上检查公开文件、核心目录、单元测试与应用构建，并保存本机签名的应用压缩包。需要 GUI 的集成检查不在无桌面 CI 中强行运行。

## 练习与隐私

基础功能无需辅助功能、屏幕录制、Apple Events 或全局键盘监听。按键始终由使用者亲自操作。

- 文本练习使用原生控件和系统剪贴板，不上传文本。
- Finder 练习创建专用样例目录；重新准备生成新目录，保留旧文件。
- 最小化和关闭使用独立练习窗口，教学主窗口保留；隐藏应用后可通过 Dock 返回。
- 浏览器练习使用本地样例网页；阅读器等依赖既有网页的操作沿用当前环境。
- 悬浮提示条不抢键盘焦点。自动验证依据实际结果，不因收到组合键就报告成功。

练习目录位于 `Library/Application Support/QuickKey/Practice/`。更多信息见 [安全与隐私](SECURITY.md)。

## 数据与图标

目录位于 `Sources/ShortcutCore/Resources/shortcuts.json`，保留每项操作的用途、前提、教学信息、预期结果和官方来源。

- [目录统计与来源](docs/shortcut-catalog.md)
- [F1–F12 与 Fn 差异](docs/function-keys.md)
- [贡献指南](CONTRIBUTING.md)
- [发布前检查](docs/open-source-checklist.md)
- [更新记录](CHANGELOG.md)

图标由 `scripts/generate-icon.swift` 使用原生绘图生成，包含 16–1024px 标准及 Retina 尺寸；不分发系统字体文件。可单独重新生成：

```sh
swift scripts/generate-icon.swift Assets
```

## 开源许可与适用范围

项目代码、原创教学文案和生成图标以 [MIT License](LICENSE) 发布。快捷键事实按 Apple 与 Google 的官方文档核对；Apple、macOS、Finder、Safari、Chrome 及相关标识属于各自权利人，本项目与这些公司无隶属或背书关系。

功能键和快捷键可能因机型、软件版本、键盘布局或个人设置而异。当前构建已在开发机验证，其他系统与硬件组合仍需实测；浏览器界面状态不宣称自动检测。
