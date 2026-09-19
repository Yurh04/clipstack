import SwiftUI
import ClipStackCore

/// 用于 .sheet(item:) 的包装，保证 id 非 nil
struct PreviewWrapper: Identifiable {
    let id = UUID()
    let item: ClipboardItem
}

/// 图片全屏预览视图（空格键触发）
struct ImagePreviewView: View {
    let item: ClipboardItem
    let imageStorage: ImageStorage
    let onCopy: (ClipboardItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage? = nil
    @State private var zoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text(formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("复制") { onCopy(item) }
                        .keyboardShortcut("c", modifiers: [.command])
                    Button("−") { zoom = max(1, zoom - 0.25) }
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit()
                        .frame(minWidth: 44)
                    Button("+") { zoom = min(4, zoom + 0.25) }
                    Button("适应") { zoom = 1 }
                }
                .buttonStyle(.bordered)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // 图片区域
            if let img = image {
                GeometryReader { proxy in
                    let viewportWidth = max(1, proxy.size.width - 32)
                    let viewportHeight = max(1, proxy.size.height - 32)
                    let fitScale = min(
                        viewportWidth / max(img.size.width, 1),
                        viewportHeight / max(img.size.height, 1)
                    )
                    // 图片本身严格按同一个比例缩放；视口不足时由 ScrollView
                    // 提供滚动区域，不能分别把宽高撑满，否则会拉伸变形。
                    let imageWidth = max(1, img.size.width * fitScale * zoom)
                    let imageHeight = max(1, img.size.height * fitScale * zoom)

                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageWidth, height: imageHeight)
                            .frame(
                                minWidth: viewportWidth,
                                minHeight: viewportHeight,
                                alignment: .center
                            )
                            .padding(16)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 900, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            image = await loadFullImage()
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: item.createdAt)
    }

    private func loadFullImage() async -> NSImage? {
        let storage = imageStorage
        let path = item.content
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? storage.load(path: path) else { return nil }
            return NSImage(data: data)
        }.value
    }
}
