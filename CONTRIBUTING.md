# 参与贡献

欢迎报告问题、修正快捷键或提交功能改进。提交内容按项目的 MIT 许可发布。

## 本地开发

需要 macOS 14+ 和 Swift 6 工具链。运行 `swift run QuickKey`，打包使用 `./scripts/build-app.sh`。

提交前运行：

```sh
./scripts/check-core.sh
./scripts/check-publication.py
./scripts/build-app.sh
```

有完整 Xcode 时额外运行 `swift test`。有交互式桌面时运行 `dist/QuickKey.app/Contents/MacOS/QuickKey --integration-test` 验证原生文本、文件、窗口与滚动条几何行为。

## 修改目录

数据位于 `Sources/ShortcutCore/Resources/shortcuts.json`。新增条目需提供唯一 ID、用途、前提、步骤、预期结果和官方来源；有硬件、语言或版本差异时写入说明。不要把应用快捷键与键帽的媒体功能混为一谈。

新增软件需要扩展 `AppScope` 并添加对应数据；导航根据实际目录生成软件入口，超过四个分类时使用“更多”菜单，选中的软件始终可见。

## 修改交互

- 条目整行可点击，保持 48pt 高度和固定右侧按键区域。
- 分类抽屉使用轻微弹簧动画，尊重系统“减少动态效果”。
- 滚动条始终占用固定槽位，测试短列表和长列表切换。
- 自动检测必须验证实际状态，不能仅因收到按键就显示成功。
- 文件操作只作用于工具创建的练习目录，不清理用户原有文件。

## 报告问题

请提供 macOS、键盘/目标软件版本、复现步骤和预期现象。截图前移除个人资料、文件路径与令牌。安全问题请参考 [SECURITY.md](SECURITY.md)。
