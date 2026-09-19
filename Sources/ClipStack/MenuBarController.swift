import AppKit
import SwiftUI
import ClipStackCore

/// 菜单栏控制器：管理菜单栏图标和下拉菜单
@MainActor
public final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let historyStore: HistoryStore
    private let onTogglePanel: () -> Void
    private let onQuit: () -> Void

    public init(
        historyStore: HistoryStore,
        onTogglePanel: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.historyStore = historyStore
        self.onTogglePanel = onTogglePanel
        self.onQuit = onQuit
    }

    /// 显示菜单栏图标
    public func show() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ClipStackIcon.menuBarImage()
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// 隐藏菜单栏图标
    public func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            onTogglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        // 统计信息
        let count = (try? historyStore.all().count) ?? 0
        let statsItem = NSMenuItem(title: "历史记录：\(count) 条", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(.separator())

        // 打开面板
        menu.addItem(NSMenuItem(
            title: "打开面板",
            action: #selector(menuTogglePanel),
            keyEquivalent: "v"
        ))

        menu.addItem(.separator())

        // 退出
        menu.addItem(NSMenuItem(
            title: "退出 ClipStack",
            action: #selector(menuQuit),
            keyEquivalent: "q"
        ))

        // 设置 target
        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // 点击后立即清除，避免影响左键点击行为
    }

    @objc private func menuTogglePanel() {
        onTogglePanel()
    }

    @objc private func menuQuit() {
        onQuit()
    }
}
