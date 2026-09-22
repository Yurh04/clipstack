import Foundation
import ImageIO
import UniformTypeIdentifiers
import ClipStackCore

/// One serial executor owns managed-image creation, insertion and orphan cleanup.
/// This prevents cleanup racing with an image that has not yet been inserted.
actor ClipboardPipeline {
    static let shared = ClipboardPipeline()
    enum Input: Sendable {
        case text(String)
        case files([URL])
        case image(Data)
    }

    func ingest(_ inputs: [Input], source: String?, store: HistoryStore, storage: ImageStorage) throws -> [ClipboardItem] {
        var result: [ClipboardItem] = []
        for input in inputs {
            switch input {
            case .text(let text):
                result.append(try store.save(ClipboardItem(type: .text, content: text, sourceApp: source)))
            case .files(let urls):
                var others: [String] = []
                for url in urls {
                    if ImageFileClassifier.isImageFile(at: url) {
                        let hash = try? ImageStorage.sha256File(at: url)
                        result.append(try store.save(ClipboardItem(type: .image, content: url.path, sourceApp: source, contentHash: hash)))
                    } else { others.append(url.path) }
                }
                if !others.isEmpty {
                    result.append(try store.save(ClipboardItem(type: .file, content: others.joined(separator: "\n"), sourceApp: source)))
                }
            case .image(let data):
                guard let png = Self.pngData(data) else { continue }
                let path = try storage.save(pngData: png)
                result.append(try store.save(ClipboardItem(type: .image, content: path, sourceApp: source, contentHash: ImageStorage.sha256Hex(png))))
            }
        }
        try maintain(store: store, storage: storage, retentionDays: UserDefaults.standard.integer(forKey: "ClipStack.retentionDays"))
        return result
    }

    func maintain(store: HistoryStore, storage: ImageStorage, retentionDays: Int = 0) throws {
        if retentionDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) {
            _ = try store.deleteExpired(olderThan: cutoff)
        }
        try store.enforceCapacityAndCleanupImages(imageStorage: storage)
    }

    func bootstrap(store: HistoryStore, storage: ImageStorage) throws {
        try store.backfillImageHashes(with: storage)
        try maintain(store: store, storage: storage, retentionDays: UserDefaults.standard.integer(forKey: "ClipStack.retentionDays"))
    }

    private static func pngData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if CGImageSourceGetType(source) as String? == UTType.png.identifier { return data }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? output as Data : nil
    }
}
