import AppKit
import UniformTypeIdentifiers
import ClipStackCore

@MainActor
public final class ClipboardDropImporter {
    private let store: HistoryStore
    private let imageStorage: ImageStorage
    public init(store: HistoryStore, imageStorage: ImageStorage) {
        self.store = store
        self.imageStorage = imageStorage
    }

    @discardableResult
    public func importProviders(_ providers: [NSItemProvider], sourceApp: String? = NSWorkspace.shared.frontmostApplication?.localizedName) async -> [ClipboardItem] {
        var inputs: [ClipboardPipeline.Input] = []
        var urls: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let data = await loadData(provider, type: UTType.fileURL.identifier),
               let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                urls.append(url)
                continue
            }
            let imageType = ([UTType.png.identifier, UTType.tiff.identifier] + provider.registeredTypeIdentifiers)
                .first { UTType($0)?.conforms(to: .image) == true && provider.hasItemConformingToTypeIdentifier($0) }
            if let imageType, let data = await loadData(provider, type: imageType) {
                inputs.append(.image(data))
                continue
            }
            if provider.canLoadObject(ofClass: NSString.self), let text = await loadText(provider), !text.isEmpty {
                inputs.append(.text(text))
            }
        }
        if !urls.isEmpty { inputs.insert(.files(urls), at: 0) }
        do {
            return try await ClipboardPipeline.shared.ingest(inputs, source: sourceApp, store: store, storage: imageStorage)
        } catch {
            AppSettings.shared.message = "导入失败：\(error.localizedDescription)"
            return []
        }
    }

    private func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: object as? String)
            }
        }
    }
}
