# 开源发布检查

发布前在项目目录运行：

```sh
./scripts/check-publication.py
./scripts/check-core.sh
./scripts/build-app.sh
./scripts/build-dmg.sh --skip-build
```

有桌面会话时运行 `dist/QuickKey.app/Contents/MacOS/QuickKey --integration-test`。有完整 Xcode 时额外运行 `swift test`。不要将未执行的远程 CI 或其他 macOS 版本称为已验证。

- 使用 MIT 许可，保留作者和来源说明；官方快捷键事实由 Apple、Google 文档核对，教学文案为项目编写。
- 发布范围只包含源码、数据、测试、脚本、文档、图标。练习目录、用户剪贴板、浏览器登录会话、构建缓存、日志和本地应用包不纳入源码仓库。
- Git 提交使用公开昵称和 GitHub noreply 地址，不写入私人邮箱。
- `check-publication.py` 会扫描已跟踪和未忽略的源文件，拒绝常见令牌、私钥、个人主目录和构建产物；它不能代替人工审阅。
- 提交前检查 `git diff --cached --stat`、`git diff --cached --check` 和实际发布文件列表。
- 公共截图由应用自己的内容视图生成，仅展示样例，不使用用户桌面截图。
- 工作流只读仓库权限，外部 Actions 固定到版本提交，检出时不持久保存凭据。
- 中英文 README 提供下载、安装与构建步骤，明确当前构建未做 Apple 公证。
- 远程仓库确认属于目标账号且为 public 后上传；不复用无关仓库。

此文件描述发布流程。仓库 URL、最终提交 SHA 和远程 CI 结论以实际发布结果为准。
