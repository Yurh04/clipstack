import AppKit
import ClipStackCore

/// Pasteboard snapshots stay on the main actor. Expensive image work is serialized off it.
@MainActor
public final class ClipboardMonitor {
    private let store: HistoryStore
    private let imageStorage: ImageStorage
    private var timer: DispatchSourceTimer?
    private var lastChangeCount = 0
    private var ignoredChangeCounts = Set<Int>()
    private var pending: Task<Void, Never>?

    public init(store: HistoryStore, imageStorage: ImageStorage) {
        self.store = store
        self.imageStorage = imageStorage
    }

    public func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.checkPasteboard() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        ignoredChangeCounts.removeAll()
    }

    public func ignorePasteboardChangeCount(_ count: Int) {
        ignoredChangeCounts.insert(count)
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let ignored = ignoredChangeCounts.contains(count)
        ignoredChangeCounts = ignoredChangeCounts.filter { $0 > count }
        guard !ignored else { return }
        let app = NSWorkspace.shared.frontmostApplication
        if let id = app?.bundleIdentifier, AppSettings.shared.excludedApps.contains(id) { return }
        guard !SensitiveContentDetector.isSensitive(pasteboardTypes: pb.types?.map(\.rawValue) ?? []) else { return }

        let inputs: [ClipboardPipeline.Input]
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []).compactMap { $0 as? URL }
        if !urls.isEmpty { inputs = [.files(urls)] }
        else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) { inputs = [.image(data)] }
        else if let text = pb.string(forType: .string), !text.isEmpty { inputs = [.text(text)] }
        else { return }
        // A provider can change while delivering data. Never persist a mixed snapshot.
        guard pb.changeCount == count else { return }
        let previous = pending
        let store = store, storage = imageStorage, source = app?.localizedName
        pending = Task {
            await previous?.value
            do {
                _ = try await ClipboardPipeline.shared.ingest(inputs, source: source, store: store, storage: storage)
            } catch { AppSettings.shared.message = "记录失败：\(error.localizedDescription)" }
        }
    }
}
