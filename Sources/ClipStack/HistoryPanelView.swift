import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClipStackCore

/// 历史面板主视图
@MainActor
public struct HistoryPanelView: View {
    @StateObject private var viewModel: HistoryPanelViewModel
    @State private var showSearchHelp = false
    @FocusState private var searchFocused: Bool
    @AppStorage("ClipStack.pinned") private var isWindowPinned = true

    private let onPinnedChange: (Bool) -> Void

    fileprivate static let acceptedDropTypes: [UTType] = [
        .fileURL,
        .image,
        .png,
        .tiff,
        .jpeg,
        .gif,
        .utf8PlainText,
        .rtf,
        .text
    ]

    public init(
        historyStore: HistoryStore,
        imageStorage: ImageStorage,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onPinnedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: HistoryPanelViewModel(
            historyStore: historyStore,
            imageStorage: imageStorage,
            onPaste: onPaste,
            onCopy: onCopy
        ))
        self.onPinnedChange = onPinnedChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryPicker
            if viewModel.selectedCategory == .favorites {
                favoriteTypePicker
                Picker("收藏标签", selection: $viewModel.selectedTag) {
                    Text("全部标签").tag("")
                    ForEach(viewModel.availableTags, id: \.self) { Text($0).tag($0) }
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            if viewModel.filteredItems.isEmpty {
                emptyView
            } else {
                historyList
            }
            if !viewModel.pendingDeletions.isEmpty {
                HStack {
                    Text("已删除 \(viewModel.pendingDeletions.count) 条 · 10 秒内可撤销")
                    Spacer()
                    Button("撤销最近一次") { viewModel.undoLastDeletion() }
                }.font(.caption).padding(10)
            }
            if !viewModel.operationMessage.isEmpty {
                Text(viewModel.operationMessage).font(.caption).foregroundStyle(.secondary).padding(6)
            }
            Text("↑↓ 选择 · ⌘C 复制 · ↩ 粘贴 · ⌘⇧S 收藏 · ⌘⌫ 删除 · ⌘Z 撤销")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(6)
        }
        .frame(minWidth: 420, minHeight: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(
            of: Self.acceptedDropTypes,
            delegate: ClipboardDropDelegate(viewModel: viewModel)
        )
        .overlay {
            if viewModel.isDropTargeted {
                dropOverlay
            }
        }
        .onKeyPress(keys: ["s"]) { press in
            guard !searchFocused, !viewModel.isEditingNote, viewModel.textPreviewItem == nil, press.modifiers == [.command, .shift],
                  let item = viewModel.selectedItem else { return .ignored }
            viewModel.toggleFavorite(item: item)
            return .handled
        }
        .onKeyPress(keys: [.delete]) { press in
            guard !searchFocused, !viewModel.isEditingNote, viewModel.textPreviewItem == nil, press.modifiers.contains(.command),
                  let item = viewModel.selectedItem else { return .ignored }
            viewModel.delete(item: item)
            return .handled
        }
        .onKeyPress(keys: ["z"]) { press in
            guard !searchFocused, !viewModel.isEditingNote, viewModel.textPreviewItem == nil, press.modifiers == .command,
                  !viewModel.pendingDeletions.isEmpty else { return .ignored }
            viewModel.undoLastDeletion()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !viewModel.isEditingNote, viewModel.textPreviewItem == nil else { return .ignored }
            searchFocused = false
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !viewModel.isEditingNote, viewModel.textPreviewItem == nil else { return .ignored }
            searchFocused = false
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.return) {
            guard !viewModel.isEditingNote, viewModel.textPreviewItem == nil else { return .ignored }
            viewModel.pasteSelected()
            return .handled
        }
        // 空格键：预览选中图片
        .onKeyPress(.space) {
            guard !searchFocused, !viewModel.isEditingNote, viewModel.textPreviewItem == nil, viewModel.canPreviewSelected else { return .ignored }
            viewModel.previewSelected()
            return .handled
        }
        .onKeyPress(keys: ["1", "2", "3", "4", "5"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.key.character {
            case "1": viewModel.selectedCategory = .all
            case "2": viewModel.selectedCategory = .text
            case "3": viewModel.selectedCategory = .image
            case "4": viewModel.selectedCategory = .file
            case "5": viewModel.selectedCategory = .favorites
            default: break
            }
            return .handled
        }
        .alert("编辑备注", isPresented: $viewModel.isEditingNote) {
            TextField("例如：测试环境地址", text: $viewModel.noteDraft)
            TextField("标签，以逗号分隔：工作, 学习", text: $viewModel.tagsDraft)
            Button("保存") { viewModel.saveNote() }
            Button("取消", role: .cancel) { viewModel.cancelEditingNote() }
        } message: {
            Text("备注和标签均参与搜索。留空可清除。")
        }
        .sheet(item: $viewModel.textPreviewItem) { wrapper in
            TextPreviewView(item: wrapper.item, onCopy: { viewModel.copy(item: wrapper.item) })
        }
        .sheet(item: $viewModel.previewItem) { wrapper in
            ImagePreviewView(
                item: wrapper.item,
                imageStorage: viewModel.imageStorage,
                onCopy: { viewModel.copy(item: $0) },
                onOCR: { viewModel.saveOCRText($0, for: wrapper.item) }
            )
        }
        // 注册为窗口级快捷键，避免搜索框焦点吞掉空格事件。
        .overlay {
            Button(action: { viewModel.previewSelected() }) {
                EmptyView()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewModel.canPreviewSelected || searchFocused || viewModel.isEditingNote || viewModel.textPreviewItem != nil)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .overlay {
            Button(action: { viewModel.copySelected() }) {
                EmptyView()
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(!viewModel.canCopySelected || searchFocused || viewModel.textPreviewItem != nil || viewModel.isEditingNote)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .task(id: viewModel.showsImageGrid) {
            guard viewModel.showsImageGrid else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                await ImageProcessing.shared.trimCaches()
            } catch { }
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
            TextField("搜索内容、备注、标签", text: $viewModel.searchText)
                .help("支持 app:Chrome type:image after:7d tag:学习；空格组合条件，双引号包裹短语")
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)

            Button { showSearchHelp.toggle() } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("搜索语法与快捷键")
            .popover(isPresented: $showSearchHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("组合搜索").font(.headline)
                    Text("app:Chrome  来源应用\ntype:image  图片（也支持 text、file）\nafter:7d  最近 7 天\ntag:学习  指定标签")
                    Text("例如：app:Chrome type:image after:7d")
                    Text("多个条件用空格分隔；完整短语用双引号包裹。")
                    Text("在搜索框外使用 ⌘⇧S 收藏、⌘⌫ 删除、⌘Z 撤销最近一次删除。")
                }.font(.caption).padding().frame(width: 330)
            }
            Button(action: toggleWindowPinned) {
                Image(systemName: isWindowPinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isWindowPinned ? "取消窗口置顶" : "将窗口固定到最前")
            .accessibilityLabel(isWindowPinned ? "取消窗口置顶" : "将窗口固定到最前")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleWindowPinned() {
        isWindowPinned.toggle()
        onPinnedChange(isWindowPinned)
    }

    private var categoryPicker: some View {
        HStack(spacing: 10) {
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

    private var favoriteTypePicker: some View {
        HStack(spacing: 8) {
            Text("收藏类型")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("全部") { viewModel.favoriteType = nil }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(viewModel.favoriteType == nil ? .accentColor : .secondary)
            ForEach(ClipboardItemType.allCases, id: \.self) { type in
                Button(typeLabel(type)) { viewModel.favoriteType = type }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(viewModel.favoriteType == type ? .accentColor : .secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 图片分类：大缩略图网格；其他分类：列表
                if viewModel.showsImageGrid {
                    imageGrid
                } else {
                    itemList
                }
            }
            .onChange(of: viewModel.selectedIndex) {
                guard viewModel.isKeyboardNavigating, let newIndex = viewModel.selectedIndex else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
                viewModel.isKeyboardNavigating = false
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
                    imageStorage: viewModel.imageStorage,
                    onFavorite: { viewModel.toggleFavorite(item: viewModel.filteredItems[index]) },
                    onPreview: {
                        searchFocused = false
                        viewModel.selectedIndex = index
                        viewModel.previewSelected()
                    }
                )
                .aspectRatio(1, contentMode: .fit)
                .id(index)
                .contextMenu {
                    Button("删除记录", role: .destructive) { viewModel.delete(item: viewModel.filteredItems[index]) }
                    Button("编辑备注与标签…") { viewModel.beginEditingNote(item: viewModel.filteredItems[index]) }
                    Button(viewModel.filteredItems[index].isFavorite ? "取消收藏" : "收藏") {
                        viewModel.toggleFavorite(item: viewModel.filteredItems[index])
                    }
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
                    },
                    onFavorite: { viewModel.toggleFavorite(item: viewModel.filteredItems[index]) },
                    onEditNote: { viewModel.beginEditingNote(item: viewModel.filteredItems[index]) },
                    onDelete: { viewModel.delete(item: viewModel.filteredItems[index]) },
                    onPreviewText: { viewModel.previewText(item: viewModel.filteredItems[index]) }
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

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.12)
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 3)
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 42))
                Text("松开以添加到对应分类")
                    .font(.system(size: 15, weight: .semibold))
                Text("支持文本、图片和文件")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.accentColor)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 辅助方法

    private func categoryLabel(_ category: ClipboardCategory) -> String {
        switch category {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .favorites: return "收藏"
        }
    }

    private func typeLabel(_ type: ClipboardItemType) -> String {
        switch type {
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
        case .favorites: return "5"
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
        case .favorites:
            if let type = viewModel.favoriteType { return "暂无收藏的\(typeLabel(type))" }
            return "暂无收藏，点击记录旁的星星即可收藏"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class HistoryPanelViewModel: ObservableObject {
    @Published var selectedCategory: ClipboardCategory = ClipboardCategory(rawValue: UserDefaults.standard.string(forKey: "ClipStack.category") ?? "all") ?? .all {
        didSet {
            UserDefaults.standard.set(selectedCategory.rawValue, forKey: "ClipStack.category")
            applyFilter()
        }
    }
    var showsImageGrid: Bool {
        selectedCategory == .image || (selectedCategory == .favorites && favoriteType == .image)
    }

    @Published var favoriteType: ClipboardItemType? {
        didSet { applyFilter() }
    }
    @Published var searchText: String = "" {
        didSet { applyFilter() }
    }
    @Published var selectedIndex: Int? = 0
    @Published var filteredItems: [ClipboardItem] = []
    @Published var previewItem: PreviewWrapper? = nil  // 空格键触发的大图预览
    @Published var textPreviewItem: PreviewWrapper? = nil
    @Published var operationMessage = ""
    @Published var pendingDeletions: [(id: Int64, deadline: Date)] = []
    @Published var selectedTag = "" { didSet { applyFilter() } }
    @Published var tagsDraft = ""
    var availableTags: [String] { Array(Set(allItems.filter(\.isFavorite).flatMap(\.tagNames))).sorted() }
    var selectedItem: ClipboardItem? {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return nil }
        return filteredItems[index]
    }
    @Published var isEditingNote = false
    @Published var noteDraft = ""
    private var editingNoteID: Int64?
    @Published var isDropTargeted = false
    var isKeyboardNavigating = false

    let historyStore: HistoryStore
    let imageStorage: ImageStorage
    let onPaste: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let dropImporter: ClipboardDropImporter

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
        self.dropImporter = ClipboardDropImporter(store: historyStore, imageStorage: imageStorage)
    }

    func reload() {
        do {
            let stored = try historyStore.all(includingPendingDeletion: true)
            allItems = stored.filter { $0.deletionDeadline == nil }
            pendingDeletions = stored.compactMap { item in
                guard let id = item.id, let deadline = item.deletionDeadline, deadline > Date() else { return nil }
                return (id, deadline)
            }.sorted { $0.deadline < $1.deadline }
            applyFilter()
        } catch {
            print("加载历史记录失败: \(error)")
        }
    }

    func importDroppedItems(_ providers: [NSItemProvider]) {
        isDropTargeted = false
        guard !providers.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            let importedItems = await self.dropImporter.importProviders(providers)
            guard !importedItems.isEmpty else { return }

            self.searchText = ""
            let importedTypes = Set(importedItems.map(\.type))
            if importedTypes.count == 1,
               let firstType = importedTypes.first,
               let category = category(for: firstType) {
                self.selectedCategory = category
            } else {
                self.selectedCategory = .all
            }
            self.reload()
            self.selectedIndex = 0
        }
    }

    /// 面板保持打开时也同步外部应用的新剪贴板内容。
    /// 仅在记录集合发生变化时刷新，避免每次轮询都重置选中项。
    func refreshWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            pendingDeletions.removeAll { $0.deadline <= Date() }
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
        isKeyboardNavigating = true
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex, current > 0 {
            selectedIndex = current - 1
        } else {
            selectedIndex = filteredItems.count - 1
        }
    }

    func moveSelectionDown() {
        isKeyboardNavigating = true
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex, current < filteredItems.count - 1 {
            selectedIndex = current + 1
        } else {
            selectedIndex = 0
        }
    }

    func pasteSelected() {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return }
        guard validateFiles(filteredItems[index]) else { return }
        onPaste(filteredItems[index])
    }

    func copySelected() {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return }
        copy(item: filteredItems[index])
    }

    func copy(item: ClipboardItem) {
        guard validateFiles(item) else { return }
        onCopy(item)
    }

    private func validateFiles(_ item: ClipboardItem) -> Bool {
        guard item.missingFilePaths.isEmpty else {
            operationMessage = "文件已不存在或无法访问，请检查原文件位置。"
            return false
        }
        operationMessage = ""
        return true
    }

    func delete(item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            let now = Date()
            try historyStore.scheduleDeletion(id: id, now: now)
            pendingDeletions.append((id, now.addingTimeInterval(10)))
            reload()
            let store = historyStore, storage = imageStorage
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                do { try await ClipboardPipeline.shared.finalizeDeletions(store: store, storage: storage) }
                catch { self?.operationMessage = "删除清理失败：\(error.localizedDescription)" }
                self?.pendingDeletions.removeAll { $0.deadline <= Date() }
            }
        } catch { operationMessage = "删除失败：\(error.localizedDescription)" }
    }

    func undoLastDeletion() {
        pendingDeletions.removeAll { $0.deadline <= Date() }
        guard let pending = pendingDeletions.last else { return }
        do {
            let restored = try historyStore.undoDeletion(id: pending.id)
            pendingDeletions.removeLast()
            reload()
            if restored { selectedIndex = filteredItems.firstIndex { $0.id == pending.id } ?? selectedIndex }
            else { operationMessage = "撤销时间已过，或记录已被清空。" }
        } catch { operationMessage = "撤销失败：\(error.localizedDescription)" }
    }

    func saveOCRText(_ text: String, for item: ClipboardItem) {
        guard let id = item.id, item.ocrText != text else { return }
        do { try historyStore.updateOCRText(id: id, text: text); reload() }
        catch { AppSettings.shared.message = "图片文字索引保存失败：\(error.localizedDescription)" }
    }

    func toggleFavorite(item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            try historyStore.updateFavorite(id: id, isFavorite: !item.isFavorite)
            reload()
            selectedIndex = filteredItems.firstIndex(where: { $0.id == id }) ?? selectedIndex
        }
        catch { AppSettings.shared.message = "收藏更新失败：\(error.localizedDescription)" }
    }

    func beginEditingNote(item: ClipboardItem) {
        editingNoteID = item.id
        noteDraft = item.note ?? ""
        tagsDraft = item.tags ?? ""
        isEditingNote = true
    }

    func cancelEditingNote() {
        editingNoteID = nil
        noteDraft = ""
    }

    func saveNote() {
        guard let id = editingNoteID else { return }
        do {
            try historyStore.updateNote(id: id, note: noteDraft)
            try historyStore.updateTags(id: id, tags: tagsDraft)
            cancelEditingNote()
            reload()
            selectedIndex = filteredItems.firstIndex(where: { $0.id == id }) ?? selectedIndex
        } catch { AppSettings.shared.message = "备注保存失败：\(error.localizedDescription)" }
    }

    func previewText(item: ClipboardItem) {
        guard item.type == .text else { return }
        textPreviewItem = PreviewWrapper(item: item)
    }

    func previewSelected() {
        guard let index = selectedIndex,
              filteredItems.indices.contains(index),
              filteredItems[index].type == .image else { return }
        guard validateFiles(filteredItems[index]) else { return }
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

    private func category(for itemType: ClipboardItemType) -> ClipboardCategory? {
        switch itemType {
        case .text: return .text
        case .image: return .image
        case .file: return .file
        }
    }

    /// 组合分类和搜索过滤，并将收藏置顶；各组保持复制时间倒序。
    private func applyFilter() {
        var items = allItems

        // 分类过滤
        switch selectedCategory {
        case .all: break
        case .text: items = items.filter { $0.type == .text }
        case .image: items = items.filter { $0.type == .image }
        case .file: items = items.filter { $0.type == .file }
        case .favorites: items = items.filter { $0.isFavorite }
        }

        if selectedCategory == .favorites, let favoriteType {
            items = items.filter { $0.type == favoriteType }
        }

        if selectedCategory == .favorites, !selectedTag.isEmpty {
            items = items.filter { $0.tagNames.contains(selectedTag) }
        }
        items = items.filter { HistorySearch.matches($0, query: searchText) }

        items = items.filter { $0.isFavorite } + items.filter { !$0.isFavorite }
        filteredItems = items
        // 过滤后重置选中到第一条
        selectedIndex = items.isEmpty ? nil : 0
    }
}

// MARK: - 剪贴板分类

enum ClipboardCategory: String, CaseIterable {
    case all
    case text
    case image
    case file
    case favorites
}

@MainActor
private final class ClipboardDropDelegate: NSObject, DropDelegate {
    private weak var viewModel: HistoryPanelViewModel?

    init(viewModel: HistoryPanelViewModel) {
        self.viewModel = viewModel
    }

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: HistoryPanelView.acceptedDropTypes).isEmpty
    }

    func dropEntered(info: DropInfo) {
        viewModel?.isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        viewModel?.isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: HistoryPanelView.acceptedDropTypes)
        viewModel?.isDropTargeted = false
        guard !providers.isEmpty else { return false }
        viewModel?.importDroppedItems(providers)
        return true
    }
}
