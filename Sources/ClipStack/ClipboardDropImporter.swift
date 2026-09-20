import AppKit
import UniformTypeIdentifiers
import ClipStackCore

/// 处理从其他应用拖入面板的文本、图片和文件。
///
/// 识别优先级与系统剪贴板监听保持一致：
/// 1. 图片文件 URL：统一归类为“图片”，直接引用原路径，不复制文件；
/// 2. 其他文件 URL：归类为“文件”，只保存路径；
/// 3. 图片数据：从浏览器或图片应用直接拖出的图片内容转成 PNG 后按哈希保存；
/// 4. 文本：选中的文字归类为“文本”。
@MainActor
public final class ClipboardDropImporter {
    private let store: HistoryStore
    private let imageStorage: ImageStorage

    public init(store: HistoryStore, imageStorage: ImageStorage) {
        self.store = store
        self.imageStorage = imageStorage
    }

    @discardableResult
    public func importProviders(
        _ providers: [NSItemProvider],
        sourceApp: String? = NSWorkspace.shared.frontmostApplication?.localizedName
    ) async -> [ClipboardItem] {
        var fileURLs: [URL] = []
        var imageItems: [ClipboardItem] = []
        var textItems: [ClipboardItem] = []

        for provider in providers {
            if let fileURL = await loadFileURL(from: provider) {
                fileURLs.append(fileURL)
                continue
            }

            if let imageData = await loadImageData(from: provider),
               let pngData = pngImageData(from: imageData) {
                do {
                    let imagePath = try imageStorage.save(pngData: pngData)
                    imageItems.append(ClipboardItem(
                        type: .image,
                        content: imagePath,
                        sourceApp: sourceApp,
                        createdAt: Date(),
                        contentHash: ImageStorage.sha256Hex(pngData)
                    ))
                } catch {
                    print("❌ ClipboardDropImporter: 拖入图片落盘失败 - \(error)")
                }
                continue
            }

            if let text = await loadText(from: provider),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textItems.append(ClipboardItem(
                    type: .text,
                    content: text,
                    sourceApp: sourceApp,
                    createdAt: Date()
                ))
            }
        }

        for url in fileURLs where ImageFileClassifier.isImageFile(at: url) {
            imageItems.append(makeLocalImageItem(url: url, sourceApp: sourceApp))
        }

        let otherFileURLs = fileURLs.filter { !ImageFileClassifier.isImageFile(at: $0) }
        var preparedItems: [ClipboardItem] = []
        if !otherFileURLs.isEmpty {
            preparedItems.append(ClipboardItem(
                type: .file,
                content: otherFileURLs.map(\.path).joined(separator: "\n"),
                sourceApp: sourceApp,
                createdAt: Date()
            ))
        }
        preparedItems.append(contentsOf: imageItems)
        preparedItems.append(contentsOf: textItems)

        var savedItems: [ClipboardItem] = []
        for item in preparedItems {
            do {
                savedItems.append(try store.save(item))
            } catch {
                print("❌ ClipboardDropImporter: 保存拖入内容失败 - \(error)")
            }
        }

        if !savedItems.isEmpty {
            do {
                try store.enforceCapacityAndCleanupImages(imageStorage: imageStorage)
            } catch {
                print("❌ ClipboardDropImporter: 容量整理失败 - \(error)")
            }
        }

        return savedItems
    }

    private func makeLocalImageItem(url: URL, sourceApp: String?) -> ClipboardItem {
        let data = try? Data(contentsOf: url)
        return ClipboardItem(
            type: .image,
            content: url.path,
            sourceApp: sourceApp,
            createdAt: Date(),
            contentHash: data.map(ImageStorage.sha256Hex)
        )
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: NSURL.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let url = object as? URL {
                        continuation.resume(returning: url.isFileURL ? url : nil)
                    } else if let url = object as? NSURL {
                        let url = url as URL
                        continuation.resume(returning: url.isFileURL ? url : nil)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        } catch {
            return nil
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard let typeIdentifier = preferredImageTypeIdentifier(for: provider) else {
            return nil
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: data)
                    }
                }
            }
        } catch {
            return nil
        }
    }

    private func preferredImageTypeIdentifier(for provider: NSItemProvider) -> String? {
        let preferredTypes: [UTType] = [.png, .tiff, .jpeg, .gif, .bmp]
        for type in preferredTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            return type.identifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else {
            return nil
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let text = object as? String {
                        continuation.resume(returning: text)
                    } else if let text = object as? NSString {
                        continuation.resume(returning: text as String)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        } catch {
            return nil
        }
    }

    private func pngImageData(from data: Data) -> Data? {
        if let bitmap = NSBitmapImageRep(data: data),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }

        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
