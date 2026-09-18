import SwiftUI
import ClipStackCore

/// 历史面板主视图
@MainActor
public struct HistoryPanelView: View {
    @StateObject private var viewModel: HistoryPanelViewModel
    @FocusState private var searchFocused: Bool

    public init(historyStore: HistoryStore, imageStorage: ImageStorage, onPaste: @escaping (ClipboardItem) -> Void) {
        _viewModel = StateObject(wrappedValue: HistoryPanelViewModel(
            historyStore: historyStore,
            imageStorage: imageStorage,
            onPaste: onPaste
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部：搜索框 + 分类
            searchField
            categoryPicker

            Divider()

            // 历史记录列表
            if viewModel.filteredItems.isEmpty {
                emptyView
            } else {
                historyList
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        // 键盘导航：绑定在最外层，聚焦搜索框时方向键/回车仍可用
        .onKeyPress(.upArrow) {
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.pasteSelected()
            return .handled
        }
        // ⌘1~4 切换分类（避免与搜索框输入冲突）
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
        .onAppear {
            viewModel.reload()
            searchFocused = true
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
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredItems.indices, id: \.self) { index in
                        HistoryItemRow(
                            item: viewModel.filteredItems[index],
                            isSelected: viewModel.selectedIndex == index,
                            imageStorage: viewModel.imageStorage
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.pasteSelected()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
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

    let historyStore: HistoryStore
    let imageStorage: ImageStorage
    let onPaste: (ClipboardItem) -> Void

    private var allItems: [ClipboardItem] = []

    init(historyStore: HistoryStore, imageStorage: ImageStorage, onPaste: @escaping (ClipboardItem) -> Void) {
        self.historyStore = historyStore
        self.imageStorage = imageStorage
        self.onPaste = onPaste
    }

    func reload() {
        do {
            allItems = try historyStore.all()
            applyFilter()
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
