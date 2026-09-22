import SwiftUI
import AppKit
import ClipStackCore

/// 用于 SwiftUI `.sheet(item:)` 的 Identifiable 包装。
struct PreviewWrapper: Identifiable {
    let id = UUID()
    let item: ClipboardItem

    init(item: ClipboardItem) {
        self.item = item
    }
}

/// 用于 .sheet(item:) 的包装，保证 id 非 nil
struct ImagePreviewSheet: View {
    let item: ClipboardItem
    let imageStorage: ImageStorage
    let onCopy: (ClipboardItem) -> Void

    var body: some View {
        ImagePreviewView(item: item, imageStorage: imageStorage, onCopy: onCopy, onOCR: { _ in })
    }
}

/// 大图预览：点击图片缩略图后弹出，支持缩放、复制、OCR 文字选择和中键拖拽平移。
struct ImagePreviewView: View {
    let item: ClipboardItem
    let imageStorage: ImageStorage
    let onCopy: (ClipboardItem) -> Void
    let onOCR: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage? = nil
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var showCopiedToast = false

    private let minimumZoom: CGFloat = 1
    private let maximumZoom: CGFloat = 4
    private let buttonZoomStep: CGFloat = 0.25

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("图片预览")
                        .font(.headline)
                    if let date = formattedDate {
                        Text(date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("复制") { copyImage() }
                    Button("−") { adjustZoom(by: -buttonZoomStep) }
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit()
                        .frame(minWidth: 44)
                    Button("+") { adjustZoom(by: buttonZoomStep) }
                    Button("适应") { resetView() }
                }
                .buttonStyle(.bordered)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 图片预览区域
            ZStack {
                Color.black

                if let image {
                    OCRImageCanvasView(
                        image: image,
                        imagePath: item.content,
                        zoom: $zoom,
                        pan: $pan,
                        zoomRange: minimumZoom...maximumZoom,
                        onCopyImage: { copyImage() },
                        onOCRRecognized: onOCR,
                        onTextCopied: { _ in showCopiedToast("文字已复制") }
                    )

                    VStack {
                        Spacer()
                        Text("左键框选图片文字，⌘C 复制 · 滚轮缩放 · 按住滚轮拖动平移")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, 12)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .colorInvert()
                        .brightness(1)
                }

                if showCopiedToast {
                    VStack {
                        Spacer()
                        Text("已复制到剪贴板")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.75))
                            )
                            .foregroundColor(.white)
                            .padding(.bottom, 48)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if image == nil {
                image = await loadFullImage()
            }
        }
    }

    private var formattedDate: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.createdAt)
    }

    private func adjustZoom(by delta: CGFloat) {
        zoom = min(maximumZoom, max(minimumZoom, zoom + delta))
    }

    private func resetView() {
        zoom = minimumZoom
        pan = .zero
    }

    private func showCopiedToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }

    private func copyImage() {
        onCopy(item)
        showCopiedToast("图片已复制")
    }

    private func loadFullImage() async -> NSImage? {
        let storage = imageStorage
        let path = item.content
        let data = await Task.detached(priority: .userInitiated) {
            try? storage.load(path: path)
        }.value
        guard let data else { return nil }
        return NSImage(data: data)
    }
}
