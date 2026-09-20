import AppKit
import SwiftUI
import Vision

/// 图片预览画布：支持 Vision OCR 文字框选、滚轮缩放、触控板平移和鼠标中键拖拽平移。
struct OCRImageCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    let zoomRange: ClosedRange<CGFloat>
    let onCopyImage: () -> Void
    let onTextCopied: (String) -> Void

    func makeNSView(context: Context) -> OCRImageCanvas {
        OCRImageCanvas(
            image: image,
            zoom: zoom,
            pan: pan,
            zoomRange: zoomRange,
            onZoomChange: { zoom = $0 },
            onPanChange: { pan = $0 },
            onCopyImage: onCopyImage,
            onTextCopied: onTextCopied
        )
    }

    func updateNSView(_ nsView: OCRImageCanvas, context: Context) {
        nsView.zoomRange = zoomRange
        nsView.onZoomChange = { zoom = $0 }
        nsView.onPanChange = { pan = $0 }
        nsView.onCopyImage = onCopyImage
        nsView.onTextCopied = onTextCopied
        nsView.updateExternalState(zoom: zoom, pan: pan)
    }
}

final class OCRImageCanvas: NSView {
    /// OCR 可选文本单元。使用字符粒度，覆盖数字、英文、标点和符号。
    private struct OCRToken: Sendable {
        let id: Int
        let text: String
        let normalizedBox: CGRect
        let range: Range<String.Index>
    }

    private struct OCRLine: Sendable {
        let text: String
        let tokens: [OCRToken]
    }

    private let image: NSImage
    private let cgImage: CGImage?
    private var lines: [OCRLine] = []
    private var tokens: [OCRToken] = []
    private var selectedTokenIDs = Set<Int>()
    private var selectionStart: CGPoint?
    private var selectionRect: CGRect?
    private var isPanning = false
    private var panStart: CGPoint = .zero
    private var panAtDragStart: CGSize = .zero

    var zoom: CGFloat
    var pan: CGSize
    var zoomRange: ClosedRange<CGFloat>
    var onZoomChange: ((CGFloat) -> Void)?
    var onPanChange: ((CGSize) -> Void)?
    var onCopyImage: (() -> Void)?
    var onTextCopied: ((String) -> Void)?

    init(
        image: NSImage,
        zoom: CGFloat,
        pan: CGSize,
        zoomRange: ClosedRange<CGFloat>,
        onZoomChange: @escaping (CGFloat) -> Void,
        onPanChange: @escaping (CGSize) -> Void,
        onCopyImage: @escaping () -> Void,
        onTextCopied: @escaping (String) -> Void
    ) {
        self.image = image
        self.cgImage = Self.makeCGImage(from: image)
        self.zoom = zoom
        self.pan = pan
        self.zoomRange = zoomRange
        self.onZoomChange = onZoomChange
        self.onPanChange = onPanChange
        self.onCopyImage = onCopyImage
        self.onTextCopied = onTextCopied
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        runOCR()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        let clampedPan = clampedPan(pan)
        if clampedPan != pan {
            updatePan(clampedPan, notify: true)
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        for token in tokens {
            let rect = tokenRect(token.normalizedBox)
            if rect.intersects(bounds) {
                addCursorRect(rect, cursor: .iBeam)
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard image.size.width > 0, image.size.height > 0 else { return }
        let imageRect = imageRect()
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        for token in tokens where selectedTokenIDs.contains(token.id) {
            let rect = tokenRect(token.normalizedBox)
            if rect.intersects(dirtyRect) {
                rect.fill()
            }
        }

        if let selectionRect {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            selectionRect.fill()
            NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
            selectionRect.frame()
        }
    }

    // MARK: - External State

    func updateExternalState(zoom newZoom: CGFloat, pan newPan: CGSize) {
        let clampedZoom = clampZoom(newZoom)
        let clampedPan = clampedPan(newPan, zoom: clampedZoom)
        let needsUpdate = zoom != clampedZoom || pan != clampedPan
        zoom = clampedZoom
        pan = clampedPan
        if newPan != clampedPan {
            DispatchQueue.main.async { [weak self] in
                self?.onPanChange?(clampedPan)
            }
        }
        if needsUpdate {
            needsDisplay = true
        }
    }

    // MARK: - Mouse: Text Selection

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2, let line = line(at: point) {
            selectedTokenIDs = Set(line.tokens.map(\.id))
            selectionStart = nil
            selectionRect = nil
            needsDisplay = true
            return
        }

        selectionStart = point
        selectionRect = CGRect(origin: point, size: .zero)
        selectedTokenIDs = []
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selectionStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(selectionStart.x, point.x),
            y: min(selectionStart.y, point.y),
            width: abs(point.x - selectionStart.x),
            height: abs(point.y - selectionStart.y)
        )
        updateSelection()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selectionRect != nil {
            selectionRect = nil
            needsDisplay = true
        }
        selectionStart = nil
    }

    // MARK: - Mouse: Middle Button Pan

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        isPanning = true
        panStart = convert(event.locationInWindow, from: nil)
        panAtDragStart = pan
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard isPanning, event.buttonNumber == 2 else {
            super.otherMouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let nextPan = CGSize(
            width: panAtDragStart.width + point.x - panStart.x,
            height: panAtDragStart.height + point.y - panStart.y
        )
        updatePan(nextPan, notify: true)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseUp(with: event)
            return
        }
        isPanning = false
        NSCursor.pop()
    }

    // MARK: - Scroll Wheel and Trackpad

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            zoomAroundMouse(event: event, deltaY: event.deltaY)
            return
        }

        let isMouseWheel = event.phase.isEmpty && event.momentumPhase.isEmpty
        if isMouseWheel {
            zoomAroundMouse(event: event, deltaY: event.deltaY)
        } else {
            // 触控板双指滚动作为平移；普通鼠标滚轮作为缩放。
            let nextPan = CGSize(
                width: pan.width + event.deltaX,
                height: pan.height + event.deltaY
            )
            updatePan(nextPan, notify: true)
        }
    }

    // MARK: - Keyboard and Menu

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "c" {
            copySmart(nil)
            return true
        }
        if key == "a" {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let clickedToken = token(at: point), !selectedTokenIDs.contains(clickedToken.id) {
            selectedTokenIDs = [clickedToken.id]
            needsDisplay = true
        }

        let menu = NSMenu()
        if !selectedText().isEmpty {
            let copyTextItem = NSMenuItem(
                title: "复制文字",
                action: #selector(copySelectedText),
                keyEquivalent: "c"
            )
            copyTextItem.target = self
            menu.addItem(copyTextItem)
        }

        let copyImageItem = NSMenuItem(title: "复制图片", action: #selector(copyFullImage), keyEquivalent: "")
        copyImageItem.target = self
        menu.addItem(copyImageItem)
        return menu
    }

    @objc func copySmart(_ sender: Any?) {
        if selectedText().isEmpty {
            copyFullImage(sender)
        } else {
            copySelectedText(sender)
        }
    }

    @objc func copySelectedText(_ sender: Any?) {
        let text = selectedText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onTextCopied?(text)
    }

    @objc func copyFullImage(_ sender: Any?) {
        onCopyImage?()
    }

    @objc override func selectAll(_ sender: Any?) {
        selectedTokenIDs = Set(tokens.map(\.id))
        needsDisplay = true
    }

    // MARK: - Geometry

    private func baseFitScale() -> CGFloat {
        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return 1
        }
        return min(bounds.width / image.size.width, bounds.height / image.size.height)
    }

    private func imageRect(zoom explicitZoom: CGFloat? = nil, pan explicitPan: CGSize? = nil) -> CGRect {
        let effectiveZoom = explicitZoom ?? zoom
        let effectivePan = explicitPan ?? pan
        let fitScale = baseFitScale()
        let size = CGSize(
            width: image.size.width * fitScale * effectiveZoom,
            height: image.size.height * fitScale * effectiveZoom
        )
        let center = CGPoint(x: bounds.midX + effectivePan.width, y: bounds.midY + effectivePan.height)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func tokenRect(_ normalizedBox: CGRect) -> CGRect {
        let rect = imageRect()
        return CGRect(
            x: rect.minX + normalizedBox.minX * rect.width,
            y: rect.minY + normalizedBox.minY * rect.height,
            width: normalizedBox.width * rect.width,
            height: normalizedBox.height * rect.height
        )
    }

    private func token(at point: CGPoint) -> OCRToken? {
        tokens.first { tokenRect($0.normalizedBox).insetBy(dx: -4, dy: -4).contains(point) }
    }

    private func line(at point: CGPoint) -> OCRLine? {
        lines.first { line in
            line.tokens.contains { tokenRect($0.normalizedBox).insetBy(dx: -6, dy: -6).contains(point) }
        }
    }

    private func updateSelection() {
        guard let selectionRect else {
            selectedTokenIDs = []
            return
        }
        selectedTokenIDs = Set(
            tokens
                .filter { tokenRect($0.normalizedBox).intersects(selectionRect) }
                .map(\.id)
        )
    }

    private func selectedText() -> String {
        lines.compactMap { line -> String? in
            let selectedTokens = line.tokens
                .filter { selectedTokenIDs.contains($0.id) }
                .sorted { $0.range.lowerBound < $1.range.lowerBound }
            guard !selectedTokens.isEmpty else { return nil }

            var pieces: [String] = []
            var currentRange: Range<String.Index>?
            for token in selectedTokens {
                guard let current = currentRange else {
                    currentRange = token.range
                    continue
                }

                let between = line.text[current.upperBound..<token.range.lowerBound]
                if between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    currentRange = current.lowerBound..<token.range.upperBound
                } else {
                    pieces.append(String(line.text[current]))
                    currentRange = token.range
                }
            }
            if let currentRange {
                pieces.append(String(line.text[currentRange]))
            }
            return pieces.joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private func zoomAroundMouse(event: NSEvent, deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let mouse = convert(event.locationInWindow, from: nil)
        let oldRect = imageRect()
        let normalizedAnchor = CGPoint(
            x: (mouse.x - oldRect.minX) / oldRect.width,
            y: (mouse.y - oldRect.minY) / oldRect.height
        )
        let normalizedDelta = max(-1, min(1, deltaY))
        let factor = 1 + normalizedDelta * 0.12
        let nextZoom = clampZoom(zoom * factor)

        let zeroPanRect = imageRect(zoom: nextZoom, pan: .zero)
        let desiredCenter = CGPoint(
            x: mouse.x + zeroPanRect.width / 2 - normalizedAnchor.x * zeroPanRect.width,
            y: mouse.y + zeroPanRect.height / 2 - normalizedAnchor.y * zeroPanRect.height
        )
        let nextPan = CGSize(
            width: desiredCenter.x - bounds.midX,
            height: desiredCenter.y - bounds.midY
        )

        zoom = nextZoom
        updatePan(nextPan, notify: true)
        onZoomChange?(nextZoom)
        needsDisplay = true
    }

    private func updatePan(_ newPan: CGSize, notify: Bool) {
        let clampedPan = clampedPan(newPan, zoom: zoom)
        pan = clampedPan
        if notify {
            onPanChange?(clampedPan)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }

    /// 限制平移范围，避免图片被完全拖出可视区域。
    private func clampedPan(_ candidate: CGSize, zoom explicitZoom: CGFloat? = nil) -> CGSize {
        let effectiveZoom = explicitZoom ?? zoom
        let rect = imageRect(zoom: effectiveZoom, pan: .zero)
        let edgeMarginX = min(40, rect.width / 2)
        let edgeMarginY = min(40, rect.height / 2)

        let minCenterX = bounds.minX + edgeMarginX - rect.width / 2
        let maxCenterX = bounds.maxX - edgeMarginX + rect.width / 2
        let minCenterY = bounds.minY + edgeMarginY - rect.height / 2
        let maxCenterY = bounds.maxY - edgeMarginY + rect.height / 2

        let centerX = bounds.midX + candidate.width
        let centerY = bounds.midY + candidate.height
        let clampedCenterX = min(maxCenterX, max(minCenterX, centerX))
        let clampedCenterY = min(maxCenterY, max(minCenterY, centerY))

        return CGSize(
            width: clampedCenterX - bounds.midX,
            height: clampedCenterY - bounds.midY
        )
    }

    // MARK: - OCR

    nonisolated private static func makeCGImage(from image: NSImage) -> CGImage? {
        if let directImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return directImage
        }

        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(
            in: CGRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return representation.cgImage
    }

    private func runOCR() {
        guard let cgImage else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { [weak self] request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let parsedLines = Self.parseObservations(observations)
                DispatchQueue.main.async {
                    self?.updateOCRLines(parsedLines)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ OCR 识别失败: \(error)")
            }
        }
    }

    private func updateOCRLines(_ newLines: [OCRLine]) {
        lines = newLines
        tokens = newLines.flatMap(\.tokens)
        selectedTokenIDs.removeAll()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    nonisolated private static func parseObservations(_ observations: [VNRecognizedTextObservation]) -> [OCRLine] {
        let sortedObservations = observations.sorted { lhs, rhs in
            let yDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDifference > 0.012 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var parsedLines: [OCRLine] = []
        var nextTokenID = 0

        for observation in sortedObservations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let recognizedText = candidate.string
            var parsedTokens = characterTokens(
                in: recognizedText,
                candidate: candidate,
                nextTokenID: &nextTokenID
            )

            // 少数情况下 Vision 不提供逐字符框，退回到词级框，避免完全无法选择。
            if parsedTokens.isEmpty {
                parsedTokens = wordTokens(
                    in: recognizedText,
                    candidate: candidate,
                    startingTokenID: nextTokenID
                )
                nextTokenID += parsedTokens.count
            }

            if parsedTokens.isEmpty {
                let fullRange = recognizedText.startIndex..<recognizedText.endIndex
                parsedTokens.append(
                    OCRToken(
                        id: nextTokenID,
                        text: recognizedText,
                        normalizedBox: observation.boundingBox,
                        range: fullRange
                    )
                )
                nextTokenID += 1
            }

            parsedLines.append(OCRLine(text: recognizedText, tokens: parsedTokens))
        }

        return parsedLines
    }

    nonisolated private static func characterTokens(
        in text: String,
        candidate: VNRecognizedText,
        nextTokenID: inout Int
    ) -> [OCRToken] {
        var parsedTokens: [OCRToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let range = index..<nextIndex
            let character = text[index]

            if !character.isWhitespace,
               let rectangle = try? candidate.boundingBox(for: range),
               rectangle.boundingBox != .zero {
                parsedTokens.append(
                    OCRToken(
                        id: nextTokenID,
                        text: String(character),
                        normalizedBox: rectangle.boundingBox,
                        range: range
                    )
                )
                nextTokenID += 1
            }

            index = nextIndex
        }

        return parsedTokens
    }

    nonisolated private static func wordTokens(
        in text: String,
        candidate: VNRecognizedText,
        startingTokenID: Int
    ) -> [OCRToken] {
        var parsedTokens: [OCRToken] = []
        var nextTokenID = startingTokenID

        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .byWords
        ) { substring, range, _, _ in
            guard let substring,
                  let rectangle = try? candidate.boundingBox(for: range),
                  rectangle.boundingBox != .zero else {
                return
            }
            parsedTokens.append(
                OCRToken(
                    id: nextTokenID,
                    text: substring,
                    normalizedBox: rectangle.boundingBox,
                    range: range
                )
            )
            nextTokenID += 1
        }

        return parsedTokens
    }
}
