import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 打开 ClipStack 面板的全局快捷键（默认 ⌘⌃J）
    static let pasteNext = Self("pasteNext", default: .init(.v, modifiers: [.command, .control]))
    static let togglePanel = Self("togglePanel", default: .init(.j, modifiers: [.command, .control]))
}
