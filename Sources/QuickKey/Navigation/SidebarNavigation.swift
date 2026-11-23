import SwiftUI
import ShortcutCore
import AppKit

private struct RowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SidebarNavigation: View {
    let catalog: ShortcutCatalog
    @ObservedObject var userState: UserLibraryState
    let selectedID: String?
    let focusSearchTrigger: Int
    let requestedScope: AppScope?
    let onHandledScopeRequest: () -> Void
    let onSelect: (String) -> Void
    let onShowSymbols: () -> Void
    let onShowSources: () -> Void

    @ViewState private var scope: AppScope = .system
    @ViewState private var query = ""
    @ViewState private var showFavoritesOnly = false
    @ViewState private var expanded: Set<String> = []
    @ViewState private var remembered: [AppScope: String] = [:]
    @ViewState private var rowFrames: [String: CGRect] = [:]
    @ViewState private var scrollTrigger = 0
    @FocusState private var searchFocused: Bool
    @StateObject private var keyCapture = KeyCaptureSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    private var scopes: [AppScope] { AppScope.allCases.filter { app in catalog.shortcuts.contains { $0.scope == app } } }
    private var visibleScopes: [AppScope] {
        SoftwarePicker.visibleIDs(in: scopes.map(\.id), selectedID: scope.id).compactMap(AppScope.init(rawValue:))
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var entries: [Shortcut] {
        let base = showFavoritesOnly
            ? catalog.shortcuts.filter { userState.isFavorite($0.id) }
            : catalog.shortcuts
        return ShortcutSearch.results(in: base, query: query, scope: (searching || showFavoritesOnly) ? nil : scope)
    }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 37, height: 37)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("快捷")).font(.system(size: 18, weight: .medium))
                    Text(L10n.text("Mac 快捷键手册")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
            searchField.padding(.horizontal, 16).padding(.bottom, 15)
            softwarePicker.padding(.horizontal, 16).padding(.bottom, 16)
            HStack {
                Text(headerTitle)
                Spacer()
                if searching {
                    Button(L10n.text("清除")) { query = "" }.buttonStyle(.plain)
                } else if showFavoritesOnly {
                    Button(L10n.text("显示全部")) { showFavoritesOnly = false }.buttonStyle(.plain)
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 23).padding(.bottom, 8)
            StableScrollView(scrollToRect: selectedID.flatMap { rowFrames[$0] }, scrollTrigger: scrollTrigger) {
                VStack(alignment: .leading, spacing: 7) {
                    if entries.isEmpty {
                        Text(showFavoritesOnly && !searching
                             ? L10n.text("还没有收藏的快捷键。点击详情页右上角的星标即可收藏。")
                             : L10n.text("没有匹配项，试试“截图”或“F12”。"))
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(18)
                    } else if searching || showFavoritesOnly {
                        ForEach(scopes) { app in
                            let matches = entries.filter { $0.scope == app }
                            if !matches.isEmpty {
                                Text(label(for: app)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
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
                .coordinateSpace(name: "sidebar-scroll")
                .onPreferenceChange(RowFramesPreferenceKey.self) { rowFrames = $0 }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            }
            .id(scope.rawValue + (searching ? "-search" : showFavoritesOnly ? "-favorites" : "-browse"))
            Divider().padding(.horizontal, 18)
            HStack(spacing: 13) {
                Button(action: onShowSymbols) { Image(systemName: "keyboard") }
                    .buttonStyle(.plain).help(L10n.text("认识键盘符号")).accessibilityLabel(L10n.text("认识键盘符号"))
                Button {
                    withAnimation(spring) { showFavoritesOnly.toggle() }
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(showFavoritesOnly ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(showFavoritesOnly ? L10n.text("显示全部") : L10n.text("仅显示收藏"))
                .accessibilityLabel(showFavoritesOnly ? L10n.text("显示全部") : L10n.text("仅显示收藏"))
                Button(L10n.format("{0} 个操作 · 来源", String(describing: catalog.shortcuts.count)), action: onShowSources).buttonStyle(.plain)
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.vertical, 15)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedID) { _, _ in revealSelection() }
        .onChange(of: focusSearchTrigger) { _, _ in
            keyCapture.stop()
            searchFocused = true
        }
        .onChange(of: requestedScope) { _, target in
            guard let target else { return }
            selectScope(target)
            onHandledScopeRequest()
        }
        .onAppear(perform: revealSelection)
        .onDisappear { keyCapture.stop() }
        .accessibilityIdentifier("shortcut-navigation")
    }

    private var headerTitle: String {
        if searching {
            return L10n.searchResultCount(entries.count)
        }
        if showFavoritesOnly {
            return L10n.text("收藏")
        }
        return label(for: scope) + L10n.text(" 快捷键")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: keyCapture.isRecording ? "record.circle.fill" : "magnifyingglass")
                .foregroundStyle(keyCapture.isRecording ? Color.accentColor : Color.secondary)
            TextField(keyCapture.isRecording ? L10n.text("正在监听按键… 按 Esc 取消") : L10n.text("搜索操作或快捷键"), text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    if keyCapture.isRecording {
                        keyCapture.stop()
                        return .handled
                    }
                    if !query.isEmpty {
                        query = ""
                        return .handled
                    }
                    searchFocused = false
                    return .handled
                }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .accessibilityLabel(L10n.text("搜索操作、软件或快捷键"))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("清空搜索"))
            }
            Button {
                searchFocused = false
                keyCapture.toggle { captured in
                    query = captured
                }
            } label: {
                Image(systemName: keyCapture.isRecording ? "keyboard.fill" : "command")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(keyCapture.isRecording ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(keyCapture.isRecording ? L10n.text("取消按键录制") : L10n.text("按组合键搜索"))
            .accessibilityLabel(keyCapture.isRecording ? L10n.text("取消按键录制") : L10n.text("按组合键搜索"))
        }.font(.system(size: 12)).padding(.horizontal, 11).padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(keyCapture.isRecording ? Color.accentColor.opacity(0.6) : .primary.opacity(0.06)))
    }

    private var softwarePicker: some View {
        HStack(spacing: 4) {
            ForEach(visibleScopes) { app in
                let isSelected = !showFavoritesOnly && scope == app
                Button { selectScope(app) } label: {
                    softwareLabel(title: label(for: app), symbol: app.symbol)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14).fill(.background)
                                    .shadow(color: .black.opacity(0.045), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "software-selection", in: selectionAnimation)
                            }
                        }
                }
                .buttonStyle(NavigationPressStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("software-" + app.id)
            }
            if SoftwarePicker.needsOverflow(scopes.map(\.id)) {
                Menu {
                    ForEach(scopes) { app in
                        Button { selectScope(app) } label: {
                            if !showFavoritesOnly && app == scope { Label(label(for: app), systemImage: "checkmark") }
                            else { Text(label(for: app)) }
                        }
                    }
                } label: { softwareLabel(title: L10n.text("更多"), symbol: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help(L10n.text("选择更多软件"))
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
                .padding(.leading, 6)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -3)), removal: .opacity))
            }
        }
        .accessibilityIdentifier("section-" + key)
    }

    private func shortcutButton(_ shortcut: Shortcut) -> some View {
        let isSelected = selectedID == shortcut.id
        let isPracticed = userState.isPracticed(shortcut.id)
        let isFavorite = userState.isFavorite(shortcut.id)
        let separator = AppLanguage.current == .english ? ", " : "，"
        return Button {
            withAnimation(spring) { onSelect(shortcut.id) }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(shortcut.title).font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange.opacity(0.85))
                            .accessibilityHidden(true)
                    }
                    if isPracticed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green.opacity(0.85))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortcut.keys.joined(separator: " ")).font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 80, alignment: .trailing).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.12))
                        .matchedGeometryEffect(id: "shortcut-selection", in: selectionAnimation)
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramesPreferenceKey.self,
                    value: [shortcut.id: proxy.frame(in: .named("sidebar-scroll"))]
                )
            })
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NavigationPressStyle())
        .help(shortcut.title + " · " + shortcut.englishKeys)
        .accessibilityLabel(shortcut.title + separator + shortcut.englishKeys)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("shortcut-" + shortcut.id)
    }

    private var sections: [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    private func selectScope(_ app: AppScope) {
        keyCapture.stop()
        showFavoritesOnly = false
        query = ""
        let item = remembered[app].flatMap { id in catalog.shortcuts.first { $0.id == id } }
            ?? catalog.shortcuts.first { $0.scope == app }
        withAnimation(spring) { scope = app; if let item { onSelect(item.id) } }
    }

    private func revealSelection() {
        guard let item = catalog.shortcuts.first(where: { $0.id == selectedID }) else { return }
        if !showFavoritesOnly {
            scope = item.scope
        }
        remembered[item.scope] = item.id
        expanded.insert(item.scope.id + "::" + item.section)
    }

    private func moveSelection(_ delta: Int) {
        let visible = entries.filter { searching || showFavoritesOnly || expanded.contains($0.scope.id + "::" + $0.section) }
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(visible.count - 1, max(0, index + delta))
        withAnimation(spring) { onSelect(visible[next].id) }
        scrollTrigger += 1
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
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(Color.primary.opacity(hovered ? 0.09 : (expanded ? 0.07 : 0.05)),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NavigationPressStyle()).onHover { hovered = $0 }
        .accessibilityLabel(title).accessibilityValue(expanded ? L10n.text("已展开") : L10n.text("已收起"))
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
