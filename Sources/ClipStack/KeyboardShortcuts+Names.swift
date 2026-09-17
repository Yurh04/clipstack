import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 打开 ClipStack 面板的全局快捷键（默认 ⌘⇧V）
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}
