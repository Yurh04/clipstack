import SwiftUI
import ClipStackCore

/// 单条历史记录行视图
struct HistoryItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let imageStorage: ImageStorage
    let onTap: () -> Void
    let onCopy: (() -> Void)?
    let onFavorite: () -> Void
    let onEditNote: () -> Void
    let onDelete: () -> Void
    let onPreviewText: () -> Void

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                leadingIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(previewText)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    if let note = item.note, !note.isEmpty {
                        Text(note).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    if !item.tagNames.isEmpty {
                        Text(item.tagNames.map { "#" + $0 }.joined(separator: " "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !item.missingFilePaths.isEmpty {
                        Label("文件已不存在或无法访问", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
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
                typeLabel
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if item.type == .text {
                Button(action: onPreviewText) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("预览全文")
            }
            if item.isFavorite {
                Button(action: onEditNote) { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .help("编辑备注")
            }
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(item.isFavorite ? "取消收藏" : "收藏并保留")

            if (item.type == .file || item.type == .text), let onCopy {
                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(item.type == .file ? "复制文件到系统剪贴板" : "复制文本到系统剪贴板")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contextMenu {
            if item.type == .text {
                Button("预览全文", action: onPreviewText)
            }
            Button("编辑备注与标签…", action: onEditNote)
            Button("删除记录", role: .destructive, action: onDelete)
        }
        .task(id: item.id) {
            // 异步加载图片缩略图
            if item.type == .image {
                thumbnail = await loadThumbnail()
            }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var leadingIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)

        case .image:
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .cornerRadius(4)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        )
                }
            }

        case .file:
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
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
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }

    // MARK: - 异步加载

    private func loadThumbnail() async -> NSImage? {
        guard let data = await ImageProcessing.shared.thumbnail(path: item.content, pixels: 88) else { return nil }
        return NSImage(data: data)
    }
}
