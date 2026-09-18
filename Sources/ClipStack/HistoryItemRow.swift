import SwiftUI
import ClipStackCore

/// 单条历史记录行视图
struct HistoryItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let imageStorage: ImageStorage

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标或缩略图
            leadingIcon

            // 中间内容预览
            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                // 来源应用和时间
                HStack(spacing: 8) {
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(timeAgo)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 右侧类型标签
            typeLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }

    // MARK: - 子视图

    @ViewBuilder
    private var leadingIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)

        case .image:
            if let imageData = try? imageStorage.load(path: item.content),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 40)
            }

        case .file:
            Image(systemName: "doc")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
        }
    }

    private var typeLabel: some View {
        Text(typeText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
    }

    // MARK: - 计算属性

    private var previewText: String {
        switch item.type {
        case .text:
            return item.content.isEmpty ? "(空)" : item.content
        case .image:
            return "图片"
        case .file:
            let paths = item.content.split(separator: "\n")
            if paths.count == 1 {
                return URL(fileURLWithPath: String(paths[0])).lastPathComponent
            } else {
                return "\(paths.count) 个文件"
            }
        }
    }

    private var typeText: String {
        switch item.type {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    private var timeAgo: String {
        let seconds = Date().timeIntervalSince(item.createdAt)
        if seconds < 60 {
            return "刚刚"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60)) 分钟前"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600)) 小时前"
        } else {
            return "\(Int(seconds / 86400)) 天前"
        }
    }
}
