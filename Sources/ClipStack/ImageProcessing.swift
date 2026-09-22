import Foundation
import ImageIO
import Vision
import UniformTypeIdentifiers
import ClipStackCore

struct OCRToken: Codable, Sendable {
    let id: Int
    let text: String
    let normalizedBox: CGRect
    let lower: Int
    let upper: Int
    func range(in string: String) -> Range<String.Index> {
        string.index(string.startIndex, offsetBy: lower)..<string.index(string.startIndex, offsetBy: upper)
    }
}
struct OCRLine: Codable, Sendable {
    let text: String
    let tokens: [OCRToken]
}

/// Serial ImageIO/Vision worker; no NSImage/AppKit drawing on background threads.
actor ImageProcessing {
    static let shared = ImageProcessing()
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipStack", isDirectory: true)
    let thumbnails = DiskCache(directory: root.appendingPathComponent("thumbnails"), limit: 64 * 1024 * 1024)
    let ocrCache = DiskCache(directory: root.appendingPathComponent("ocr"), limit: 32 * 1024 * 1024)

    func fingerprint(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "v1|\(url.standardizedFileURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    func thumbnail(path: String, pixels: Int) async -> Data? {
        guard let key = try? fingerprint(path) else { return nil }
        let cacheKey = "\(key)|\(pixels)"
        if let data = await thumbnails.data(for: cacheKey) { return data }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { return nil }
        let result = data as Data
        try? await thumbnails.put(result, for: cacheKey, trimAfterWrite: false)
        return result
    }

    func recognize(path: String) async throws -> (key: String, lines: [OCRLine]) {
        let key = try fingerprint(path)
        if let data = await ocrCache.data(for: key), let lines = try? JSONDecoder().decode([OCRLine].self, from: data) {
            return (key, lines)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:]).perform([request])
        let observations = (request.results ?? []).sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        var lines: [OCRLine] = []
        var nextID = 0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            guard !text.isEmpty else { continue }
            var tokens: [OCRToken] = []
            for (offset, index) in text.indices.enumerated() where !text[index].isWhitespace {
                let end = text.index(after: index)
                if let rectangle = try? candidate.boundingBox(for: index..<end), rectangle.boundingBox != .zero {
                    tokens.append(OCRToken(id: nextID, text: String(text[index]), normalizedBox: rectangle.boundingBox, lower: offset, upper: offset + 1))
                    nextID += 1
                }
            }
            if tokens.isEmpty {
                tokens.append(OCRToken(id: nextID, text: text, normalizedBox: observation.boundingBox, lower: 0, upper: text.count))
                nextID += 1
            }
            lines.append(OCRLine(text: text, tokens: tokens))
        }
        // Discard results if the referenced file changed while recognition ran.
        guard try fingerprint(path) == key else { throw CocoaError(.fileReadUnknown) }
        try await ocrCache.put(JSONEncoder().encode(lines), for: key)
        return (key, lines)
    }

    func trimCaches() async {
        try? await thumbnails.trimToLimit()
        try? await ocrCache.trimToLimit()
    }

    func clearCaches() async throws {
        try await thumbnails.clear()
        try await ocrCache.clear()
    }
    func cacheBytes() async throws -> Int {
        let a = try await thumbnails.size()
        let b = try await ocrCache.size()
        return a + b
    }
}
