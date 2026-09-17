import AppKit
import ClipStackCore

/// 剪贴板监听器：轮询 NSPasteboard.changeCount，检测到变化时解析并存储。
///
/// **架构设计**：
/// - 使用 Timer 轮询而非 DistributedNotificationCenter（后者不可靠且有延迟）
/// - 敏感内容检测与图片落盘逻辑已在 ClipStackCore 中单元测试覆盖
/// - 本类只负责 AppKit 层面的事件获取和类型识别，靠集成测试（手动验证）确保正确
@MainActor
public final class ClipboardMonitor {
    private let store: HistoryStore
    private let imageStorage: ImageStorage
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    public init(store: HistoryStore, imageStorage: ImageStorage) {
        self.store = store
        self.imageStorage = imageStorage
    }

    /// 启动监听（每 0.5 秒轮询一次）
    public func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    /// 停止监听
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 轮询与解析

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 敏感内容检测
        let types = pb.types?.map(\.rawValue) ?? []
        guard !SensitiveContentDetector.isSensitive(pasteboardTypes: types) else {
            return  // 跳过密码等敏感内容
        }

        // 解析剪贴板内容
        if let item = parseClipboardItem(from: pb) {
            do {
                try store.save(item)
                try store.enforceCapacity()
            } catch {
                print("❌ ClipboardMonitor: 存储失败 - \(error)")
            }
        }
    }

    private func parseClipboardItem(from pb: NSPasteboard) -> ClipboardItem? {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // 1. 图片（优先级最高，因为复制图片时也可能带文本描述）
        if let tiff = pb.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                let imagePath = try imageStorage.save(imageData: pngData)
                return ClipboardItem(
                    type: .image,
                    content: imagePath,
                    sourceApp: sourceApp,
                    createdAt: Date()
                )
            } catch {
                print("❌ ClipboardMonitor: 图片落盘失败 - \(error)")
                return nil
            }
        }

        // 2. 文件（Finder 复制的文件带 fileURL，需在文本之前判断——文件 URL 也能被读成字符串）
        if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            // 多个文件用换行分隔存储路径
            let paths = fileURLs.map(\.path).joined(separator: "\n")
            return ClipboardItem(
                type: .file,
                content: paths,
                sourceApp: sourceApp,
                createdAt: Date()
            )
        }

        // 3. 文本
        if let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(
                type: .text,
                content: text,
                sourceApp: sourceApp,
                createdAt: Date()
            )
        }

        return nil
    }
}
