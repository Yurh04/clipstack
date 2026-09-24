import SwiftUI
import AppKit
import ServiceManagement

/// User-controlled options. Destructive retention and login launch are opt-in.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var paused = false
    @Published var loginEnabled = false
    @Published var message = ""
    @Published var storageSummary = ""
    @Published var busy = false
    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "ClipStack.retentionDays") }
    }
    @Published var excludedApps: [String] {
        didSet { UserDefaults.standard.set(excludedApps, forKey: "ClipStack.excludedApps") }
    }
    var onPauseChange: ((Bool) -> Void)?
    var onMaintenance: (() -> Void)?
    var onStorageRefresh: (() -> Void)?
    var onClearHistory: ((Bool) -> Void)?
    var onClearCache: (() -> Void)?

    private init() {
        retentionDays = UserDefaults.standard.integer(forKey: "ClipStack.retentionDays")
        excludedApps = UserDefaults.standard.stringArray(forKey: "ClipStack.excludedApps") ?? []
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            message = "请在系统设置 → 通用 → 登录项中允许 ClipStack。"
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = ""
        } catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        refreshLogin()
    }

    func togglePause() {
        paused.toggle()
        onPauseChange?(paused)
    }

    func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "排除这些应用"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            if !excludedApps.contains(id) { excludedApps.append(id) }
        }
    }
}

struct ClipStackSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var confirmRetention = false
    @State private var confirmClearHistory = false
    @State private var includingFavorites = false

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时启动 ClipStack", isOn: Binding(
                    get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
                Text("建议将应用放在“应用程序”目录后开启；状态以 macOS 登录项为准。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(settings.paused ? "恢复记录" : "暂停记录") { settings.togglePause() }
                Text("暂停期间不记录系统剪贴板，手动拖入仍可使用；恢复时不补录暂停期间的内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("隐私") {
                Button("添加排除的应用…") { settings.addExcludedApp() }
                ForEach(settings.excludedApps, id: \.self) { id in
                    HStack {
                        Text(id).textSelection(.enabled)
                        Spacer()
                        Button("移除") { settings.excludedApps.removeAll { $0 == id } }
                    }
                }
                Text("仅影响今后的自动记录，不删除旧记录。主动拖入视为手动导入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("历史与存储") {
                Picker("自动清理普通历史", selection: $settings.retentionDays) {
                    Text("关闭").tag(0)
                    Text("超过 7 天").tag(7)
                    Text("超过 30 天").tag(30)
                    Text("超过 90 天").tag(90)
                }
                Text("设置后在后续维护时生效。收藏不参与按天或条数淘汰；本地原文件永不删除。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("立即按规则整理") { confirmRetention = true }
                    Button("刷新占用") { settings.onStorageRefresh?() }
                    Button("清理可再生缓存") { settings.onClearCache?() }
                }.disabled(settings.busy)
                HStack {
                    Button("清空普通历史…") {
                        includingFavorites = false
                        confirmClearHistory = true
                    }
                    Button("清空全部历史…", role: .destructive) {
                        includingFavorites = true
                        confirmClearHistory = true
                    }
                }.disabled(settings.busy)
                if settings.busy { ProgressView().controlSize(.small) }
                Text(settings.storageSummary).font(.caption).textSelection(.enabled)
            }
            if !settings.message.isEmpty {
                Text(settings.message).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 610)
        .onAppear { settings.refreshLogin(); settings.onStorageRefresh?() }
        .confirmationDialog(includingFavorites ? "清空全部历史，包括收藏和备注？此操作不可撤销。" : "清空普通历史？收藏及其备注会保留。此操作不可撤销。", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(includingFavorites ? "清空全部（含收藏）" : "清空普通历史", role: .destructive) {
                settings.onClearHistory?(includingFavorites)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("本地原文件不会删除。")
        }
        .confirmationDialog("按当前规则删除过期或超出容量的普通历史？收藏和本地原文件不会删除。", isPresented: $confirmRetention) {
            Button("整理普通历史", role: .destructive) { settings.onMaintenance?() }
        }
    }
}
