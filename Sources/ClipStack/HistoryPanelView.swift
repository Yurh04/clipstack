import SwiftUI
import ClipStackCore

/// 历史面板主视图
@MainActor
public struct HistoryPanelView: View {
    @StateObject private var viewModel: HistoryPanelViewModel
    @FocusState private var searchFocused: Bool

    public init(
        historyStore: HistoryStore,
        imageStorage: ImageStorage,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HistoryPanelViewModel(
            historyStore: historyStore,
            imageStorage: imageStorage,
            onPaste: onPaste,
            onCopy: onCopy
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryPicker
            Divider()
            if viewModel.filteredItems.isEmpty {
                emptyView
            } else {
                historyList
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onKeyPress(.upArrow) {
            searchFocused = false
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            searchFocused = false
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.pasteSelected()
            return .handled
        }
        // 空格键：预览选中图片
        .onKeyPress(.space) {
            guard viewModel.canPreviewSelected else { return .ignored }
            viewModel.previewSelected()
            return .handled
        }
        .onKeyPress(keys: ["1", "2", "3", "4"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.key.character {
            case "1": viewModel.selectedCategory = .all
            case "2": viewModel.selectedCategory = .text
            case "3": viewModel.selectedCategory = .image
            case "4": viewModel.selectedCategory = .file
            default: break
            }
            return .handled
        }
        .sheet(item: $viewModel.previewItem) { wrapper in
            ImagePreviewView(
                item: wrapper.item,
                imageStorage: viewModel.imageStorage,
                onCopy: { viewModel.copy(item: $0) }
            )
        }
        // 注册为窗口级快捷键，避免搜索框焦点吞掉空格事件。
        .overlay {
            Button(action: { viewModel.previewSelected() }) {
                EmptyView()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewModel.canPreviewSelected)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .overlay {
            Button(action: { viewModel.copySelected() }) {
                EmptyView()
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(!viewModel.canCopySelected || searchFocused)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .onAppear {
            viewModel.reload()
            searchFocused = true
        }
        .task {
            await viewModel.refreshWhileVisible()
        }
    }

    // MARK: - 子视图

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索剪贴板历史", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.space) {
                    guard viewModel.canPreviewSelected else { return .ignored }
                    viewModel.previewSelected()
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var categoryPicker: some View {
        HStack(spacing: 16) {
            ForEach(ClipboardCategory.allCases, id: \.self) { category in
                Button(action: {
                    viewModel.selectedCategory = category
                }) {
                    HStack(spacing: 4) {
                        Text(categoryLabel(category))
                            .font(.system(size: 13, weight: viewModel.selectedCategory == category ? .semibold : .regular))
                        Text("⌘\(categoryShortcut(category))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(
                    KeyEquivalent(Character(categoryShortcut(category))),
                    modifiers: [.command]
                )
                .foregroundColor(viewModel.selectedCategory == category ? .accentColor : .primary)
            }

            Spacer()

            Text("\(viewModel.filteredItems.count) 条")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 图片分类：大缩略图网格；其他分类：列表
                if viewModel.selectedCategory == .image {
                    imageGrid
                } else {
                    itemList
                }
            }
            .onChange(of: viewModel.selectedIndex) {
                if let newIndex = viewModel.selectedIndex {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // 图片网格：3 列，大尺寸方块
    private var imageGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(viewModel.filteredItems.indices, id: \.self) { index in
                ImageGridCell(
                    item: viewModel.filteredItems[index],
                    isSelected: viewModel.selectedIndex == index,
                    imageStorage: viewModel.imageStorage
                )
                .id(index)
                .onTapGesture {
                    searchFocused = false
                    viewModel.selectedIndex = index
                    // 直接点击图片打开预览，避免依赖搜索框焦点和空格事件。
                    viewModel.previewSelected()
                }
            }
        }
        .padding(10)
    }

    // 文本/文件列表
    private var itemList: some View {
        LazyVStack(spacing: 2) {
            ForEach(viewModel.filteredItems.indices, id: \.self) { index in
                HistoryItemRow(
                    item: viewModel.filteredItems[index],
                    isSelected: viewModel.selectedIndex == index,
                    imageStorage: viewModel.imageStorage,
                    onTap: {
                        searchFocused = false
                        viewModel.selectedIndex = index
                        switch ClipboardItemTapBehavior.action(for: viewModel.filteredItems[index]) {
                        case .select:
                            break
                        case .preview:
                            // 图片记录直接打开预览，避免依赖空格键焦点。
                            viewModel.previewSelected()
                        case .paste:
                            break
                        }
                    },
                    onCopy: {
                        searchFocused = false
                        viewModel.selectedIndex = index
                        viewModel.copy(item: viewModel.filteredItems[index])
                    }
                )
                .id(index)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(emptyMessage)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 辅助方法

    private func categoryLabel(_ category: ClipboardCategory) -> String {
        switch category {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    private func categoryShortcut(_ category: ClipboardCategory) -> String {
        switch category {
        case .all: return "1"
        case .text: return "2"
        case .image: return "3"
        case .file: return "4"
        }
    }

    private var emptyMessage: String {
        if !viewModel.searchText.isEmpty {
            return "没有匹配「\(viewModel.searchText)」的记录"
        }
        switch viewModel.selectedCategory {
        case .all: return "暂无历史记录"
        case .text: return "暂无文本记录"
        case .image: return "暂无图片记录"
        case .file: return "暂无文件记录"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class HistoryPanelViewModel: ObservableObject {
    @Published var selectedCategory: ClipboardCategory = .all {
        didSet { applyFilter() }
    }
    @Published var searchText: String = "" {
        didSet { applyFilter() }
    }
    @Published var selectedIndex: Int? = 0
    @Published var filteredItems: [ClipboardItem] = []
    @Published var previewItem: PreviewWrapper? = nil  // 空格键触发的大图预览

    let historyStore: HistoryStore
    let imageStorage: ImageStorage
    let onPaste: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void

    private var allItems: [ClipboardItem] = []

    init(
        historyStore: HistoryStore,
        imageStorage: ImageStorage,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void
    ) {
        self.historyStore = historyStore
        self.imageStorage = imageStorage
        self.onPaste = onPaste
        self.onCopy = onCopy
    }

    func reload() {
        do {
            allItems = try historyStore.all()
            applyFilter()
        } catch {
            print("加载历史记录失败: \(error)")
        }
    }

    /// 面板保持打开时也同步外部应用的新剪贴板内容。
    /// 仅在记录集合发生变化时刷新，避免每次轮询都重置选中项。
    func refreshWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            reloadIfChanged()
        }
    }

    private func reloadIfChanged() {
        do {
            let latestItems = try historyStore.all()
            guard latestItems != allItems else { return }
            let selectedID = selectedIndex.flatMap { index in
                filteredItems.indices.contains(index) ? filteredItems[index].id : nil
            }
            let previousIndex = selectedIndex
            allItems = latestItems
            applyFilter()
            if let selectedID,
               let newIndex = filteredItems.firstIndex(where: { $0.id == selectedID }) {
                selectedIndex = newIndex
            } else if let previousIndex, !filteredItems.isEmpty {
                selectedIndex = min(previousIndex, filteredItems.count - 1)
            }
        } catch {
            print("加载历史记录失败: \(error)")
        }
    }

    func moveSelectionUp() {
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex, current > 0 {
            selectedIndex = current - 1
        } else {
            selectedIndex = filteredItems.count - 1
        }
    }

    func moveSelectionDown() {
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex, current < filteredItems.count - 1 {
            selectedIndex = current + 1
        } else {
            selectedIndex = 0
        }
    }

    func pasteSelected() {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return }
        onPaste(filteredItems[index])
    }

    func copySelected() {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return }
        onCopy(filteredItems[index])
    }

    func copy(item: ClipboardItem) {
        onCopy(item)
    }

    func previewSelected() {
        guard let index = selectedIndex,
              filteredItems.indices.contains(index),
              filteredItems[index].type == .image else { return }
        previewItem = PreviewWrapper(item: filteredItems[index])
    }

    var canPreviewSelected: Bool {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return false }
        return filteredItems[index].type == .image
    }

    var canCopySelected: Bool {
        guard let index = selectedIndex else { return false }
        return filteredItems.indices.contains(index)
    }

    /// 组合分类 + 搜索过滤（≤500 条，内存过滤足够快）
    private func applyFilter() {
        var items = allItems

        // 分类过滤
        switch selectedCategory {
        case .all: break
        case .text: items = items.filter { $0.type == .text }
        case .image: items = items.filter { $0.type == .image }
        case .file: items = items.filter { $0.type == .file }
        }

        // 搜索过滤（大小写不敏感子串）
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            items = items.filter { $0.content.range(of: keyword, options: .caseInsensitive) != nil }
        }

        filteredItems = items
        // 过滤后重置选中到第一条
        selectedIndex = items.isEmpty ? nil : 0
    }
}

// MARK: - 剪贴板分类

enum ClipboardCategory: CaseIterable {
    case all
    case text
    case image
    case file
}
