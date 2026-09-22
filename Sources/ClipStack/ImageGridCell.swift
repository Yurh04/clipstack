import SwiftUI
import ClipStackCore

/// 图片分类的网格单元格：大缩略图 + 时间标注
struct ImageGridCell: View {
    let item: ClipboardItem
    let isSelected: Bool
    let imageStorage: ImageStorage

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        // 用透明方块决定单元格尺寸，图片只作为 overlay，绝不反向影响布局，
        // 避免超长图（如 1512×23134）撑开网格导致主线程布局死循环。
        Color.secondary.opacity(0.1)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
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
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
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
        guard let data = await ImageProcessing.shared.thumbnail(path: item.content, pixels: 320) else { return nil }
        return NSImage(data: data)
    }
}
