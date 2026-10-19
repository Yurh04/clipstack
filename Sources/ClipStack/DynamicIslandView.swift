import SwiftUI
import AppKit
import ClipStackCore

/// 灵动岛浮层内容：`.peek` 显示刚记录的一条，`.expanded` 显示最近几条。
/// 只负责画界面，数据与动作都从外面注入。
struct DynamicIslandView: View {
    let state: IslandState
    let items: [ClipboardItem]
    let imageStorage: ImageStorage
    let onPaste: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onFavorite: (ClipboardItem) -> Void
    let onDownload: (ClipboardItem) -> Void
    let onDownloadTo: (ClipboardItem) -> Void
    let onHover: (Bool) -> Void

    private static let peekWidth: CGFloat = 300
    private static let expandedWidth: CGFloat = 400
    private static let cornerRadius: CGFloat = 18

    var body: some View {
        content
            .background(
                Color.black.opacity(0.92),
                in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(HoverTracker(onHover: onHover))
    }

    // MARK: - 子视图

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .peek(let item):
            peek(item)
        case .expanded:
            expanded
        }
    }

    private func peek(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            IslandTypeIcon(item: item, size: 20)
            Text(IslandPreview.preview(for: item))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("悬停展开")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(width: Self.peekWidth, height: 40)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("最近 \(items.count) 条")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                Text("点击粘贴 · 拖拽可上传")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(items.indices, id: \.self) { index in
                    IslandItemRow(
                        item: items[index],
                        onPaste: { onPaste(items[index]) },
                        onCopy: { onCopy(items[index]) },
                        onFavorite: { onFavorite(items[index]) },
                        onDownload: { onDownload(items[index]) },
                        onDownloadTo: { onDownloadTo(items[index]) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: Self.expandedWidth)
    }
}

// MARK: - 列表行

private struct IslandItemRow: View {
    let item: ClipboardItem
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDownload: () -> Void
    let onDownloadTo: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            IslandIcon(item: item, size: 22, thumbnail: thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(IslandPreview.preview(for: item))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let source = item.sourceApp, !source.isEmpty {
                    Text(source)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color.white.opacity(isHovered ? 0.14 : 0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .onHover { isHovered = $0 }
        .overlay {
            // 图片 / 文件行叠加真实文件拖拽层，可拖到「选择文件」窗口上传。
            // 文本行不需要拖拽，保留上面的单击粘贴。
            if item.type != .text {
                FileDragSource(urls: item.draggableFileURLs, image: thumbnail, onClick: onPaste)
            }
        }
        .contextMenu {
            Button("复制到剪贴板", action: onCopy)
            Button(item.isFavorite ? "取消收藏" : "收藏", action: onFavorite)
            if item.type != .text {
                Divider()
                Button("下载", action: onDownload)
                Button("下载到指定文件夹…", action: onDownloadTo)
            }
        }
        .task(id: item.id) {
            thumbnail = await islandThumbnail(for: item, pixels: 56)
        }
    }
}

// MARK: - 图标

/// 纯展示图标：图片用传入的缩略图，其余用 SF Symbol。
private struct IslandIcon: View {
    let item: ClipboardItem
    var size: CGFloat = 22
    var thumbnail: NSImage? = nil

    var body: some View {
        switch item.type {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: size * 0.62))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)

        case .file:
            Image(systemName: "doc.fill")
                .font(.system(size: size * 0.62))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)

        case .image:
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: size * 0.5))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

/// peek 态用的图标：自己异步加载图片缩略图。
private struct IslandTypeIcon: View {
    let item: ClipboardItem
    var size: CGFloat = 20

    @State private var thumbnail: NSImage?

    var body: some View {
        IslandIcon(item: item, size: size, thumbnail: thumbnail)
            .task(id: item.id) {
                thumbnail = await islandThumbnail(for: item, pixels: 56)
            }
    }
}

/// 加载图片缩略图；非图片类型直接返回 nil。
@MainActor
private func islandThumbnail(for item: ClipboardItem, pixels: Int) async -> NSImage? {
    guard item.type == .image else { return nil }
    guard let data = await ImageProcessing.shared.thumbnail(path: item.content, pixels: pixels) else { return nil }
    return NSImage(data: data)
}
