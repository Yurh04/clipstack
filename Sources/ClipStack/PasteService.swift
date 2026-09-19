import AppKit
import CoreGraphics
import ClipStackCore

/// 系统粘贴集成：将历史记录粘贴回目标应用。
///
/// **工作流程**：
/// 1. 面板弹出前记录当前前台应用（rememberedApp）
/// 2. 用户在面板选中历史项后调用 paste(item:)
/// 3. 重新激活 rememberedApp，将内容写回系统剪贴板，模拟 Cmd+V
///
/// **测试策略**：
/// - 依赖 NSPasteboard、NSWorkspace、CGEvent 系统 API，无法单元测试
/// - 靠集成测试（手动验证）确保粘贴到 Notes.app、终端、浏览器等不同应用正确
@MainActor
public final class PasteService {
    private let imageStorage: ImageStorage
    private var rememberedApp: NSRunningApplication?

    public init(imageStorage: ImageStorage) {
        self.imageStorage = imageStorage
    }

    /// 记住当前前台应用（在面板弹出前调用）
    public func rememberFrontmostApp() {
        rememberedApp = NSWorkspace.shared.frontmostApplication
    }

    /// 是否已获得辅助功能（Accessibility）权限，模拟按键需要此权限
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限，会弹出系统引导对话框（首次启动时调用）
    public static func requestAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt 的字符串值，直接用字面量避开 Swift 6 并发检查
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 将历史项粘贴到记住的应用（激活 → 写剪贴板 → 模拟 Cmd+V）
    @discardableResult
    public func paste(item: ClipboardItem) -> Bool {
        // 1. 重新激活目标应用
        if let app = rememberedApp {
            app.activate()
            Thread.sleep(forTimeInterval: 0.1)  // 给应用激活留点时间
        }

        // 2. 写回系统剪贴板
        guard copyToPasteboard(item: item) else { return false }

        // 3. 模拟 Cmd+V
        simulatePaste()
        return true
    }

    /// 只写回系统剪贴板，不切换应用，也不模拟粘贴。
    /// 用于历史记录选中后的 Cmd+C。
    @discardableResult
    public func copyToPasteboard(item: ClipboardItem) -> Bool {
        let pb = NSPasteboard.general
        // 先完成所有可能失败的读取，再动系统剪贴板。
        let payload: PasteboardPayload

        switch item.type {
        case .text:
            payload = .text(item.content)

        case .image:
            guard let imageData = try? imageStorage.load(path: item.content),
                  let image = NSImage(data: imageData) else {
                print("❌ PasteService: 无法加载图片 \(item.content)")
                return false
            }
            payload = .image(image)

        case .file:
            let paths = item.content.split(separator: "\n").map(String.init)
            guard !paths.isEmpty else { return false }
            let urls = paths.map { URL(fileURLWithPath: $0) }
            payload = .files(urls)
        }

        let previous = snapshot(of: pb)
        let previousChangeCount = pb.changeCount
        pb.clearContents()

        let didWrite: Bool
        switch payload {
        case .text(let value):
            didWrite = pb.setString(value, forType: .string)
        case .image(let image):
            didWrite = pb.writeObjects([image])
        case .files(let urls):
            didWrite = pb.writeObjects(urls as [NSURL])
        }

        guard didWrite, pb.changeCount != previousChangeCount else {
            restore(previous, to: pb)
            return false
        }
        return true
    }

    private enum PasteboardPayload {
        case text(String)
        case image(NSImage)
        case files([URL])
    }

    private typealias PasteboardSnapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - 按键模拟

    private func simulatePaste() {
        // 发送 Cmd+V 按下
        if let keyDownEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x09,  // V 键的虚拟键码
            keyDown: true
        ) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cghidEventTap)
        }

        // 发送 Cmd+V 松开
        if let keyUpEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0x09,
            keyDown: false
        ) {
            keyUpEvent.flags = .maskCommand
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }
}
