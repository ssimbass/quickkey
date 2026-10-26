import SwiftUI
import ShortcutCore
import AppKit

struct SidebarNavigation: View {
    let catalog: ShortcutCatalog
    let selectedID: String?
    let onSelect: (String) -> Void
    let onShowSymbols: () -> Void
    let onShowSources: () -> Void
    @ViewState private var scope: AppScope = .system
    @ViewState private var query = ""
    @ViewState private var expanded: Set<String> = []
    @ViewState private var remembered: [AppScope: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    private var scopes: [AppScope] { AppScope.allCases.filter { app in catalog.shortcuts.contains { $0.scope == app } } }
    private var visibleScopes: [AppScope] {
        SoftwarePicker.visibleIDs(in: scopes.map(\.id), selectedID: scope.id).compactMap(AppScope.init(rawValue:))
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var entries: [Shortcut] {
        ShortcutSearch.results(in: catalog.shortcuts, query: query, scope: searching ? nil : scope)
    }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 37, height: 37)
                VStack(alignment: .leading, spacing: 2) {
                    Text("快捷").font(.system(size: 18, weight: .medium))
                    Text("Mac 快捷键手册").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
            searchField.padding(.horizontal, 16).padding(.bottom, 15)
            softwarePicker.padding(.horizontal, 16).padding(.bottom, 16)
            HStack {
                Text(searching ? "\(entries.count) 个搜索结果" : label(for: scope) + " 快捷键")
                Spacer()
                if searching {
                    Button("清除") { query = "" }.buttonStyle(.plain)
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 23).padding(.bottom, 8)
            StableScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if entries.isEmpty {
                        Text("没有匹配项，试试“截图”或“F12”。")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(18)
                    } else if searching {
                        ForEach(scopes) { app in
                            let matches = entries.filter { $0.scope == app }
                            if !matches.isEmpty {
                                Text(label(for: app)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 14).padding(.top, 9)
                                ForEach(matches) { shortcut in shortcutButton(shortcut) }
                            }
                        }
                    } else {
                        ForEach(sections, id: \.self) { section in
                            drawer(section)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            }
            .id(scope.rawValue + (searching ? "-search" : "-browse"))
            Divider().padding(.horizontal, 18)
            HStack(spacing: 13) {
                Button(action: onShowSymbols) { Image(systemName: "keyboard") }
                    .buttonStyle(.plain).help("认识键盘符号").accessibilityLabel("认识键盘符号")
                Button("\(catalog.shortcuts.count) 个操作 · 来源", action: onShowSources).buttonStyle(.plain)
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.vertical, 15)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedID) { _, _ in revealSelection() }
        .onAppear(perform: revealSelection)
        .accessibilityIdentifier("shortcut-navigation")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索操作或快捷键", text: $query).textFieldStyle(.plain)
                .accessibilityLabel("搜索操作、软件或快捷键")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("清空搜索")
            }
        }.font(.system(size: 12)).padding(.horizontal, 11).padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06)))
    }

    private var softwarePicker: some View {
        HStack(spacing: 4) {
            ForEach(visibleScopes) { app in
                Button { selectScope(app) } label: {
                    softwareLabel(title: label(for: app), symbol: app.symbol)
                        .foregroundStyle(scope == app ? Color.accentColor : Color.primary)
                        .background {
                            if scope == app {
                                RoundedRectangle(cornerRadius: 14).fill(.background)
                                    .shadow(color: .black.opacity(0.045), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "software-selection", in: selectionAnimation)
                            }
                        }
                }
                .buttonStyle(NavigationPressStyle())
                .accessibilityAddTraits(scope == app ? .isSelected : [])
                .accessibilityIdentifier("software-" + app.id)
            }
            if SoftwarePicker.needsOverflow(scopes.map(\.id)) {
                Menu {
                    ForEach(scopes) { app in
                        Button { selectScope(app) } label: {
                            if app == scope { Label(label(for: app), systemImage: "checkmark") }
                            else { Text(label(for: app)) }
                        }
                    }
                } label: { softwareLabel(title: "更多", symbol: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("选择更多软件")
            }
        }
        .animation(spring, value: scope)
    }

    private func softwareLabel(title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
            Text(title).font(.system(size: 11)).lineLimit(1)
        }.frame(maxWidth: .infinity).frame(height: 67).contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func drawer(_ section: String) -> some View {
        let key = scope.id + "::" + section
        let open = expanded.contains(key)
        let list = entries.filter { $0.section == section }
        return VStack(spacing: 3) {
            DrawerHeader(title: section, count: list.count, expanded: open) {
                withAnimation(spring) {
                    if open { expanded.remove(key) } else { expanded.insert(key) }
                }
            }
            if open {
                VStack(spacing: 3) {
                    ForEach(list) { shortcut in shortcutButton(shortcut) }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -3)), removal: .opacity))
            }
        }
        .accessibilityIdentifier("section-" + key)
    }

    private func shortcutButton(_ shortcut: Shortcut) -> some View {
        Button {
            withAnimation(spring) { onSelect(shortcut.id) }
        } label: {
            HStack(spacing: 8) {
                Text(shortcut.title).font(.system(size: 12, weight: selectedID == shortcut.id ? .medium : .regular))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(shortcut.keys.joined(separator: " ")).font(.system(size: 11))
                    .foregroundStyle(selectedID == shortcut.id ? Color.accentColor : Color.secondary)
                    .frame(width: 80, alignment: .trailing).lineLimit(1)
            }
            .foregroundStyle(selectedID == shortcut.id ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 48)
            .background {
                if selectedID == shortcut.id {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.12))
                        .matchedGeometryEffect(id: "shortcut-selection", in: selectionAnimation)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NavigationPressStyle())
        .help(shortcut.title + " · " + shortcut.englishKeys)
        .accessibilityLabel(shortcut.title + "，" + shortcut.englishKeys)
        .accessibilityAddTraits(selectedID == shortcut.id ? .isSelected : [])
        .accessibilityIdentifier("shortcut-" + shortcut.id)
    }

    private var sections: [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    private func selectScope(_ app: AppScope) {
        query = ""
        let item = remembered[app].flatMap { id in catalog.shortcuts.first { $0.id == id } }
            ?? catalog.shortcuts.first { $0.scope == app }
        withAnimation(spring) { scope = app; if let item { onSelect(item.id) } }
    }

    private func revealSelection() {
        guard let item = catalog.shortcuts.first(where: { $0.id == selectedID }) else { return }
        scope = item.scope
        remembered[item.scope] = item.id
        expanded.insert(item.scope.id + "::" + item.section)
    }

    private func moveSelection(_ delta: Int) {
        let visible = entries.filter { searching || expanded.contains($0.scope.id + "::" + $0.section) }
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(visible.count - 1, max(0, index + delta))
        withAnimation(spring) { onSelect(visible[next].id) }
    }

    private func label(for app: AppScope) -> String { app == .system ? "macOS" : app.title }
}

private struct DrawerHeader: View {
    let title: String
    let count: Int
    let expanded: Bool
    let action: () -> Void
    @ViewState private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: 45)
            .background(hovered ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NavigationPressStyle()).onHover { hovered = $0 }
        .accessibilityLabel(title).accessibilityValue(expanded ? "已展开" : "已收起")
    }
}

struct NavigationPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressFeedback(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PressFeedback<Label: View>: View {
    let label: Label
    let pressed: Bool
    @ViewState private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label
            .background(hovered ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7), value: pressed)
            .onHover { hovered = $0 }
    }
}
