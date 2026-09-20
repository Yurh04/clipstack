# ClipStack

原生 macOS 剪贴板历史工具，使用 SwiftUI、AppKit 和 Swift Package Manager 构建。

## 下载

前往 [GitHub Releases](https://github.com/Yurh04/clipstack/releases/latest) 下载 DMG 或 ZIP。
首版支持 Apple Silicon、macOS 14+，尚未经过 Developer ID 签名和 Apple 公证；安装说明见 [v0.1.0 发布说明](docs/releases/v0.1.0.md)。

## 当前功能

- 自动记录文本、图片和文件路径，历史记录保存在本机。
- 按全部、文本、图片、文件分类，支持搜索。
- 所有图片来源统一归入“图片”分类；本地图片文件直接引用原路径，不重复复制。
- 剪贴板图片按 SHA-256 哈希存储，相同图片只保留一份；历史淘汰后自动清理无引用图片。
- 文本和文件单击只选中，点击右侧“复制”按钮写回系统剪贴板。
- 图片网格与图片预览，预览支持按钮、鼠标滚轮缩放、OCR 框选中文/英文/数字/符号复制，以及按住鼠标滚轮拖拽平移。
- 支持将选中文本、图片或文件直接拖入面板，自动归类并加入历史。
- 面板可通过搜索栏右侧按钮切换置顶状态。
- 取消置顶后，点击菜单栏图标会在原位置重新置前；关闭后重新打开会恢复上次关闭位置。
- 面板可拖动边缘调整宽高。
- 默认保留最近 500 条历史记录，跳过带有敏感剪贴板标记的内容。

## 运行

需要 macOS 14 或更新版本，以及支持 Swift 6 的 Xcode / Command Line Tools。

```sh
./script/build_and_run.sh --verify
```

脚本构建并启动 `dist/ClipStack.app`。依赖由 SwiftPM 自动下载。

模拟粘贴到其他应用需要在系统设置中授予辅助功能权限。

## 操作

| 操作 | 快捷键或入口 |
| --- | --- |
| 显示 / 隐藏面板 | `⌘⌃J` 或菜单栏图标 |
| 被其他窗口挡住时重新置前 | 菜单栏图标 |
| 切换分类 | `⌘1` ～ `⌘4` |
| 选择记录 | 点击记录或方向键 |
| 复制所选记录 | `⌘C`（搜索框未聚焦时） |
| 粘贴到原应用 | `Return` |
| 预览图片 | 点击图片或选中后按空格 |
| 复制图片中的文字 | 预览时左键拖拽框选文字，按 `⌘C` 或右键选择“复制文字” |
| 缩放预览图片 | 图片预览中滚动鼠标滚轮，或使用 `+` / `−` |
| 移动缩放后的图片 | 按住鼠标滚轮（中键）拖动；触控板可双指拖动 |
| 导入内容 | 将文本、图片或文件拖入面板 |
| 切换窗口置顶 | 搜索栏右侧图钉按钮 |

## 本地存储

- 数据库：`~/Library/Application Support/ClipStack/history.db`
- 剪贴板图片：`~/Library/Application Support/ClipStack/images/<SHA-256>.png`
- 文本直接存入 SQLite。
- 非图片文件只保存路径，不复制文件本体。
- 本地图片文件作为“图片”记录保存原路径，不复制到 `images/` 目录；原文件移动或删除后该记录可能无法继续使用。
- 只有 App 拿不到原文件路径的图片数据，才会写入 `images/` 并按哈希去重。

## 开发与验证

```sh
swift test
swift build -c release --product ClipStack
```

打包 DMG、ZIP 和 SHA-256 校验文件（需要 Python 3，产物位于 `dist/releases/`）：

```sh
./script/package_release.sh 0.1.0 1
```

单元测试覆盖存储、过滤、容量限制、图片哈希去重、孤儿图片清理、图片文件识别、敏感类型判断和点击行为映射；系统剪贴板、辅助功能及真实鼠标交互仍需在 macOS 上验证。

历史数据位于 `~/Library/Application Support/ClipStack/`。文件记录保存原文件路径，原文件移动或删除后可能无法继续使用。

`docs/superpowers/specs/` 保留早期设计方案，当前行为以代码和本文为准。
