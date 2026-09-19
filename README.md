# ClipStack

原生 macOS 剪贴板历史工具，使用 SwiftUI、AppKit 和 Swift Package Manager 构建。

## 下载

前往 [GitHub Releases](https://github.com/Yurh04/clipstack/releases/latest) 下载 DMG 或 ZIP。
首版支持 Apple Silicon、macOS 14+，尚未经过 Developer ID 签名和 Apple 公证；安装说明见 [v0.1.0 发布说明](docs/releases/v0.1.0.md)。

## 当前功能

- 自动记录文本、图片和文件路径，历史记录保存在本机。
- 按全部、文本、图片、文件分类，支持搜索。
- 文本和文件单击只选中，点击右侧“复制”按钮写回系统剪贴板。
- 图片网格与图片预览，预览支持缩放和复制。
- 面板在鼠标所在位置打开，可拖动边缘调整宽高。
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
| 切换分类 | `⌘1` ～ `⌘4` |
| 选择记录 | 点击记录或方向键 |
| 复制所选记录 | `⌘C`（搜索框未聚焦时） |
| 粘贴到原应用 | `Return` |
| 预览图片 | 点击图片或选中后按空格 |

## 开发与验证

```sh
swift test
swift build -c release --product ClipStack
```

打包 DMG、ZIP 和 SHA-256 校验文件（需要 Python 3，产物位于 `dist/releases/`）：

```sh
./script/package_release.sh 0.1.0 1
```

单元测试覆盖存储、过滤、容量限制、敏感类型判断和点击行为映射；系统剪贴板、辅助功能及真实鼠标交互仍需在 macOS 上验证。

历史数据位于 `~/Library/Application Support/ClipStack/`。文件记录保存原文件路径，原文件移动或删除后可能无法继续使用。

`docs/superpowers/specs/` 保留早期设计方案，当前行为以代码和本文为准。
