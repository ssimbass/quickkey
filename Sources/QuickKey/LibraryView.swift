import SwiftUI
import AppKit
import ShortcutCore

struct LibraryView: View {
    let catalog: ShortcutCatalog
    @ObservedObject var practice: PracticeController
    @ViewState private var selectedID: String?
    @ViewState private var showSymbols = false
    @ViewState private var showSources = false
    @AppStorage("lastSelectedShortcutID") private var lastSelectedID = "system-spotlight"
    private var selected: Shortcut? { catalog.shortcuts.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            SidebarNavigation(catalog: catalog, selectedID: selectedID, onSelect: choose,
                              onShowSymbols: { showSymbols.toggle() }, onShowSources: { showSources.toggle() })
                .frame(width: 320)
            Divider()
            ScrollView {
                if let selected {
                    ShortcutDetailView(shortcut: selected, catalog: catalog, practice: practice)
                        .id(selected.id)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(30)
                }
            }
            .id(selectedID)
            .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .popover(isPresented: $showSources) { SourcesView(catalog: catalog) }
        .popover(isPresented: $showSymbols) {
            VStack(alignment: .leading, spacing: 13) {
                Text("键盘符号").font(.headline)
                ForEach([("⌘", "Command"), ("⌥", "Option"), ("⇧", "Shift"), ("⌃", "Control"), ("↩", "Return"), ("Fn", "Function")], id: \.0) { pair in
                    HStack(spacing: 10) { KeyCaps(keys: [pair.0]); Text(pair.1).font(.system(size: 12)) }
                }
            }.padding(20)
        }
        .onAppear { DispatchQueue.main.async { restoreSelection() } }
        .onDisappear { practice.hideFloatingHint() }
    }

    private func choose(_ id: String) {
        guard selectedID != id, let shortcut = catalog.shortcuts.first(where: { $0.id == id }) else { return }
        practice.stop()
        selectedID = id
        if shortcut.practice == .textEditing { practice.prepare(shortcut) }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test") && !ProcessInfo.processInfo.arguments.contains("--integration-test") {
            lastSelectedID = id
        }
    }

    private func restoreSelection() {
        guard selectedID == nil else { return }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--preview-shortcut"), args.indices.contains(i + 1),
           catalog.shortcuts.contains(where: { $0.id == args[i + 1] }) { choose(args[i + 1]) }
        else if catalog.shortcuts.contains(where: { $0.id == lastSelectedID }) { choose(lastSelectedID) }
        else if let first = catalog.shortcuts.first { choose(first.id) }
    }
}

struct KeyCaps: View {
    let keys: [String]
    var large = false
    var body: some View {
        HStack(spacing: large ? 8 : 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: large ? 23 : 12))
                    .padding(.horizontal, large ? 15 : 6)
                    .frame(minWidth: large ? 49 : 25, minHeight: large ? 46 : 25)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: large ? 9 : 5))
                    .overlay(RoundedRectangle(cornerRadius: large ? 9 : 5).strokeBorder(.primary.opacity(0.12)))
                    .shadow(color: .black.opacity(0.06), radius: 0, x: 0, y: 2)
                    .fixedSize()
            }
        }
    }
}

struct SourcesView: View {
    let catalog: ShortcutCatalog
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("目录来源").font(.title2.weight(.medium))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("\(catalog.shortcuts.count) 个操作 · 核对日期 \(catalog.verifiedAt)").foregroundStyle(.secondary)
            HStack(spacing: 22) {
                ForEach(AppScope.allCases) { scope in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scope.title).font(.caption).foregroundStyle(.secondary)
                        Text("\(catalog.shortcuts.filter { $0.scope == scope }.count)").font(.title3.monospacedDigit())
                    }
                }
            }
            Divider()
            ForEach(catalog.sources) { source in
                Link(destination: source.url) { Label(source.title, systemImage: "arrow.up.right.square") }
                    .font(.system(size: 12))
            }
            Text("收录官方默认绑定。实际组合键可能随软件版本、键盘布局和个人设置变化，请以当前应用菜单为准。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 560)
    }
}
