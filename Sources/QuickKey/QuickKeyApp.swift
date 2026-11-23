import SwiftUI
import AppKit
import ShortcutCore

// Keep the property wrapper available with SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct QuickKeyApp: App {
    @NSApplicationDelegateAdaptor(QuickKeyAppDelegate.self) private var delegate
    @StateObject private var library = LibraryModel()
    @StateObject private var practice = PracticeController()
    @StateObject private var userState = UserLibraryState()
    @ViewState private var focusSearchTrigger = 0
    @ViewState private var requestedScope: AppScope?
    @AppStorage("appLanguage") private var languagePreference = "system"
    @StateObject private var menuBarModel = MenuBarShortcutModel()
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        WindowGroup(L10n.text("快捷 · Mac 快捷键手册"), id: "main") {
            Group {
                if let catalog = library.catalog {
                    LibraryView(
                        catalog: catalog,
                        practice: practice,
                        userState: userState,
                        focusSearchTrigger: focusSearchTrigger,
                        requestedScope: requestedScope,
                        onHandledScopeRequest: { requestedScope = nil }
                    )
                } else {
                    ContentUnavailableView {
                        Label(L10n.text("目录暂时无法打开"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(library.error ?? L10n.text("请重新启动应用。"))
                    } actions: {
                        Button(L10n.text("重新加载")) { library.load() }
                    }
                    .frame(minWidth: 720, minHeight: 480)
                }
            }
            .frame(minWidth: 820, minHeight: 560)
            .tint(.blue)
            .id(languagePreference)
            .environment(\.locale, Locale(identifier: AppLanguage.current.rawValue))
            .onAppear {
                let isTestRun = ProcessInfo.processInfo.arguments.contains("--smoke-test")
                    || ProcessInfo.processInfo.arguments.contains("--integration-test")
                let state = userState
                practice.onVerified = isTestRun ? nil : { [weak state] id in
                    state?.markPracticed(id)
                }
            }
            .background(
                MenuBarBridgeView(
                    library: library,
                    model: menuBarModel,
                    controller: menuBarController
                )
            )
            .onChange(of: languagePreference) { _, _ in
                practice.stop()
                library.load()
            }
        }
        .defaultSize(width: 1060, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
            TextEditingCommands()
            TextFormattingCommands()
            CommandMenu(L10n.text("导航")) {
                Button(L10n.text("搜索快捷键")) {
                    focusSearchTrigger += 1
                }
                .keyboardShortcut("f", modifiers: .command)
                Divider()
                ForEach(Array(AppScope.allCases.enumerated()), id: \.element.id) { index, scope in
                    if let key = KeyEquivalent.digit(index + 1) {
                        Button(scope == .system ? "macOS" : scope.title) {
                            requestedScope = scope
                        }
                        .keyboardShortcut(key, modifiers: .command)
                    }
                }
            }
            CommandGroup(after: .help) {
                Button(L10n.text("打开快捷键官方来源")) {
                    let locale = AppLanguage.current == .english ? "en-us" : "zh-cn"
                    NSWorkspace.shared.open(URL(string: "https://support.apple.com/\(locale)/102650")!)
                }
            }
        }
        Settings {
            SettingsView(practice: practice)
        }
    }
}

/// Connects SwiftUI scene actions (`openWindow`, `openSettings`) to the AppKit menu bar controller.
private struct MenuBarBridgeView: View {
    let library: LibraryModel
    let model: MenuBarShortcutModel
    let controller: MenuBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                controller.configure(
                    library: library,
                    model: model,
                    openMainWindow: { openWindow(id: "main") },
                    openSettings: { openSettings() }
                )
            }
    }
}

private extension KeyEquivalent {
    static func digit(_ number: Int) -> KeyEquivalent? {
        guard (1...9).contains(number), let character = String(number).first else { return nil }
        return KeyEquivalent(character)
    }
}

@MainActor
final class UserLibraryState: ObservableObject {
    @Published private(set) var store: UserLibraryStore

    init() {
        self.store = UserLibraryStore.load()
    }

    func isFavorite(_ id: String) -> Bool { store.isFavorite(id) }
    func isPracticed(_ id: String) -> Bool { store.isPracticed(id) }

    func toggleFavorite(_ id: String) {
        store.toggleFavorite(id)
        store.save()
    }

    func markPracticed(_ id: String) {
        if store.markPracticed(id) {
            store.save()
        }
    }
}

@MainActor
final class QuickKeyAppDelegate: NSObject, NSApplicationDelegate {
    private var checkingLastWindowClose = false

    static var isTestRun: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--smoke-test") || arguments.contains("--integration-test")
    }

    /// With the menu bar panel enabled, closing the last window keeps QuickKey running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.isTestRun || !MenuBarPreference.isEnabled
    }

    func applicationWillTerminate(_ notification: Notification) {
        if checkingLastWindowClose {
            print("窗口生命周期检查通过：关闭最后一个窗口后应用自动退出。")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--integration-test") {
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(1))
                    let catalog = try ShortcutCatalog.load()
                    print(try await PracticeIntegrationChecks.run(catalog: catalog))
                    print(try await NavigationGeometryChecks.run())
                    let windows = NSApp.windows.filter { $0.isVisible || $0.isMiniaturized }
                    guard !windows.isEmpty else {
                        fputs("INTEGRATION CHECK FAILED: no window available to close\n", stderr)
                        exit(1)
                    }
                    checkingLastWindowClose = true
                    for window in windows { window.performClose(nil) }
                    // Success must come from AppKit's last-window termination, not the test itself.
                    try await Task.sleep(for: .seconds(2))
                    fputs("INTEGRATION CHECK FAILED: closing the last window left the application running\n", stderr)
                    exit(1)
                } catch {
                    fputs("INTEGRATION CHECK FAILED: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let catalog = try? ShortcutCatalog.load(), let window = NSApp.windows.first(where: { $0.isVisible }),
                      let view = window.contentView else {
                    fputs("SMOKE TEST FAILED: catalog or window missing\n", stderr)
                    NSApp.terminate(nil)
                    return
                }
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        let arguments = ProcessInfo.processInfo.arguments
                        var name = "quickkey-native"
                        if let index = arguments.firstIndex(of: "--preview-shortcut"), arguments.indices.contains(index + 1),
                           catalog.shortcuts.contains(where: { $0.id == arguments[index + 1] }) {
                            name = "quickkey-" + arguments[index + 1]
                        }
                        name += AppLanguage.current == .english ? "-en" : "-zh-CN"
                        let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            .appendingPathComponent("dist/\(name).png")
                        try? data.write(to: destination)
                    }
                }
                print("SMOKE TEST PASSED: \(catalog.shortcuts.count) shortcuts; window \(Int(view.bounds.width))×\(Int(view.bounds.height))")
                NSApp.terminate(nil)
            }
        }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var catalog: ShortcutCatalog?
    @Published private(set) var error: String?

    init() { load() }
    func load() {
        do { catalog = try ShortcutCatalog.load(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

enum MenuBarPreference {
    static let key = "showMenuBarExtra"
    static let defaultValue = true
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue }
}

struct SettingsView: View {
    @ObservedObject var practice: PracticeController
    @AppStorage("showWindowsEquivalent") private var showWindowsEquivalent = true
    @AppStorage(MenuBarPreference.key) private var showMenuBarExtra = MenuBarPreference.defaultValue
    @AppStorage("appLanguage") private var languagePreference = "system"
    @ViewState private var folderCount = 0
    @ViewState private var folderBytes: Int64 = 0
    @ViewState private var cleanupMessage: String?

    var body: some View {
        Form {
            Picker(L10n.text("语言"), selection: $languagePreference) {
                Text(L10n.text("跟随系统")).tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh-Hans")
            }
            Toggle(L10n.text("显示 Windows 对照"), isOn: $showWindowsEquivalent)
            Toggle(isOn: $showMenuBarExtra) {
                Text(L10n.text("在菜单栏显示快捷键面板"))
                Text(L10n.text("点击菜单栏图标查看当前应用的快捷键，点击即可执行。"))
            }
            LabeledContent(L10n.text("练习方式"), value: L10n.text("准备真实环境，亲手按下快捷键"))
            LabeledContent(L10n.text("练习目录")) {
                HStack(spacing: 10) {
                    Text(folderSummaryText).foregroundStyle(.secondary)
                    Button(L10n.text("在 Finder 中打开")) {
                        if let root = try? PracticeController.practiceRootDirectory(create: true) {
                            NSWorkspace.shared.open(root)
                        }
                    }
                    Button(L10n.text("将历史目录移到废纸篓")) {
                        moveInactiveFoldersToTrash()
                    }
                    .disabled(folderCount == 0)
                }
            }
            if let cleanupMessage {
                Text(cleanupMessage).font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("文件练习使用应用创建的专用目录。基础练习无需辅助功能或全局键盘监听。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 380)
        .padding(12)
        .onAppear(perform: refreshPracticeSummary)
    }

    private var folderSummaryText: String {
        guard folderCount > 0 else { return L10n.text("暂无历史练习文件") }
        let formattedSize = ByteCountFormatter.string(fromByteCount: folderBytes, countStyle: .file)
        if folderCount == 1 {
            return L10n.format("1 个目录（{0}）", formattedSize)
        }
        return L10n.format("{0} 个目录（{1}）", String(folderCount), formattedSize)
    }

    private func refreshPracticeSummary() {
        let summary = PracticeController.practiceFolderSummary()
        folderCount = summary.count
        folderBytes = summary.bytes
    }

    private func moveInactiveFoldersToTrash() {
        do {
            let trashed = try PracticeController.trashInactivePracticeFolders(excluding: practice.practiceDirectory)
            if trashed == 0 {
                cleanupMessage = L10n.text("当前没有可清理的历史练习目录。")
            } else if trashed == 1 {
                cleanupMessage = L10n.text("已将 1 个历史练习目录移到废纸篓。")
            } else {
                cleanupMessage = L10n.format("已将 {0} 个历史练习目录移到废纸篓。", String(trashed))
            }
        } catch {
            cleanupMessage = L10n.format("清理失败：{0}", error.localizedDescription)
        }
        refreshPracticeSummary()
    }
}
