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
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var ignoredChangeCounts: Set<Int> = []

    public init(store: HistoryStore, imageStorage: ImageStorage) {
        self.store = store
        self.imageStorage = imageStorage
    }

    /// 启动监听（每 0.5 秒轮询一次）
    public func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        timer.resume()
        self.timer = timer
    }

    /// 停止监听
    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    /// 标记一个已经由 ClipStack 写入的 changeCount，避免把自己的写回保存成新历史。
    /// 使用精确 changeCount，避免误吞掉用户紧接着产生的下一条剪贴板内容。
    public func ignorePasteboardChangeCount(_ changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    // MARK: - 轮询与解析

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if ignoredChangeCounts.remove(currentCount) != nil {
            return
        }

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

        // 1. 文件优先于图片：Finder 复制文件时可能同时提供文件图标的
        // PNG/TIFF 表示，必须先识别 fileURL，避免把任意格式文件记成图片。
        if let objects = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            let fileURLs = objects.compactMap { object -> URL? in
                if let url = object as? URL {
                    return url
                }
                if let url = object as? NSURL {
                    return url as URL
                }
                return nil
            }
            if !fileURLs.isEmpty {
                // 多个文件用换行分隔存储路径
                let paths = fileURLs.map(\.path).joined(separator: "\n")
                return ClipboardItem(
                    type: .file,
                    content: paths,
                    sourceApp: sourceApp,
                    createdAt: Date()
                )
            }
        }

        // 2. 图片（复制图片时也可能同时带文本描述）。
        // 优先读取剪贴板提供的原始 PNG，避免先转成 TIFF 时丢失 Retina
        // 像素密度；只有没有 PNG 时才回退到 TIFF 转 PNG。
        if let pngData = imageData(from: pb) {
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

    private func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png),
           NSBitmapImageRep(data: pngData) != nil {
            return pngData
        }

        guard let tiffData = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
