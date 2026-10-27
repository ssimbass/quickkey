# 快捷 · QuickKey

[English](README.md) | 简体中文

原生 macOS 快捷键手册，支持动手练习。使用 SwiftUI 和 AppKit 构建。

## 界面预览

### 快捷键查阅

![快捷键查阅](docs/images/navigation.png)

### 文本编辑练习

![文本编辑练习](docs/images/practice.png)

## 功能

- 支持简体中文和英语，默认跟随系统语言，也可在设置中切换。
- 按分类查阅 macOS、Finder、Safari 和 Chrome 快捷键。
- 练习文本编辑、文件操作和窗口控制，支持的操作提供结果反馈。
- 离线使用，无第三方运行时依赖，无需辅助功能权限。

## 下载与安装

需要 **macOS 14 或更新版本**。预编译版本支持 **Apple Silicon（arm64）**。

1. 从 [Releases](https://github.com/ssimbass/quickkey/releases/latest) 下载 `.dmg`。
2. 打开后将 **QuickKey** 拖到 **Applications（应用程序）**。
3. 从「应用程序」启动 QuickKey。

应用使用本机 ad-hoc 签名，**未经过 Apple 公证**。若 macOS 拦截，先尝试打开一次，再进入 **系统设置 → 隐私与安全性 → 仍要打开** 并确认。参见 [Apple 操作说明](https://support.apple.com/102445)。

## 构建

需要 macOS 和 **Swift 6 工具链**。

```sh
git clone https://github.com/ssimbass/quickkey.git
cd quickkey
./scripts/build-app.sh
open dist/QuickKey.app
```

生成发布用 DMG：

```sh
./scripts/build-dmg.sh
```

## 开发

```sh
./scripts/check-publication.py
./scripts/check-core.sh
swift test # 需要 XCTest，完整 Xcode 提供该组件。
```

参见 [贡献指南](CONTRIBUTING.md)、[更新记录](CHANGELOG.md) 和 [安全说明](SECURITY.md)。

## 隐私

练习使用本地文本、系统剪贴板和专用样例文件，不上传练习内容。部分外部操作需手动确认，详见 [安全与隐私](SECURITY.md)。

## 许可

[MIT](LICENSE)。快捷键资料来源于 Apple 和 Google 官方文档。本项目与 Apple、Google 无隶属关系。
