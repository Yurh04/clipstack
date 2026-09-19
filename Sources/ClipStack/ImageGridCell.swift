import SwiftUI
import ClipStackCore

/// 图片分类的网格单元格：大缩略图 + 时间标注
struct ImageGridCell: View {
    let item: ClipboardItem
    let isSelected: Bool
    let imageStorage: ImageStorage

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 背景色块（加载中占位）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .aspectRatio(1, contentMode: .fit)

            // 图片
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                    )
            }

            // 右下角时间标注
            Text(timeAgo)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55))
                .cornerRadius(4)
                .padding(5)
        }
        .overlay(
            // 选中边框
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .task(id: item.id) {
            thumbnail = await loadThumbnail()
        }
    }

    private var timeAgo: String {
        let seconds = Date().timeIntervalSince(item.createdAt)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60))分前" }
        if seconds < 86400 { return "\(Int(seconds / 3600))时前" }
        return "\(Int(seconds / 86400))天前"
    }

    private func loadThumbnail() async -> NSImage? {
        let storage = imageStorage
        let path = item.content
        return await Task.detached(priority: .utility) {
            guard let data = try? storage.load(path: path),
                  let image = NSImage(data: data) else { return nil }
            // 生成 160x160 缩略图（网格用大图）
            let size: CGFloat = 160
            let thumb = NSImage(size: NSSize(width: size, height: size))
            thumb.lockFocus()
            let srcSize = image.size
            let scale = max(size / srcSize.width, size / srcSize.height)
            let drawSize = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)
            let drawRect = NSRect(
                x: (size - drawSize.width) / 2,
                y: (size - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
            thumb.unlockFocus()
            return thumb
        }.value
    }
}
