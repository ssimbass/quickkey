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

    var body: some Scene {
        WindowGroup("快捷 · Mac 快捷键手册", id: "main") {
            Group {
                if let catalog = library.catalog {
                    LibraryView(catalog: catalog, practice: practice)
                } else {
                    ContentUnavailableView {
                        Label("目录暂时无法打开", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(library.error ?? "请重新启动应用。")
                    } actions: {
                        Button("重新加载") { library.load() }
                    }
                    .frame(minWidth: 720, minHeight: 480)
                }
            }
            .frame(minWidth: 820, minHeight: 560)
            .tint(.blue)
        }
        .defaultSize(width: 1060, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
            TextEditingCommands()
            TextFormattingCommands()
            CommandGroup(after: .help) {
                Button("打开快捷键官方来源") {
                    NSWorkspace.shared.open(URL(string: "https://support.apple.com/zh-cn/102650")!)
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class QuickKeyAppDelegate: NSObject, NSApplicationDelegate {
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
                    NSApp.terminate(nil)
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

struct SettingsView: View {
    @AppStorage("showWindowsEquivalent") private var showWindowsEquivalent = true

    var body: some View {
        Form {
            Toggle("显示 Windows 对照", isOn: $showWindowsEquivalent)
            LabeledContent("练习方式", value: "准备真实环境，亲手按下快捷键")
            Text("文件练习使用应用创建的专用目录。基础练习无需辅助功能或全局键盘监听。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 195)
        .padding(12)
    }
}
