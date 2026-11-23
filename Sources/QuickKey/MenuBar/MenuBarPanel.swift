import SwiftUI
import AppKit
import ShortcutCore

/// Content of the floating menu bar panel: the current app's shortcuts, clickable to trigger.
struct MenuBarPanel: View {
    let catalog: ShortcutCatalog?
    @ObservedObject var model: MenuBarShortcutModel
    let onClose: () -> Void
    let onOpenMain: () -> Void
    let onOpenSettings: () -> Void
    let onHeightChange: () -> Void

    @Namespace private var tabNamespace
    @ViewState private var tab: Tab = .app
    @ViewState private var query = ""
    @ViewState private var hoveredID: String?

    enum Tab: Hashable { case app, system }

    static let width: CGFloat = 266
    static let listHeight: CGFloat = 280
    static let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            header
            controls
            if !model.isTrusted { permissionBanner }
            list
            footer
        }
        .frame(width: Self.width)
        .onChange(of: model.isTrusted) { _, _ in onHeightChange() }
        .onChange(of: model.targetApp?.processIdentifier) { _, _ in query = "" }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = model.targetApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            } else {
                Image(systemName: "app.dashed")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.targetApp?.localizedName ?? L10n.text("未检测到应用"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(sourceDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ClearGlassIconButton(help: L10n.text("重新读取快捷键")) {
                model.refresh()
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(spacing: 7) {
            tabSwitcher
            searchField
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 2) {
            tabButton(L10n.text("当前应用"), value: .app)
            tabButton(L10n.text("系统"), value: .system)
        }
        .padding(2)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    private func tabButton(_ title: String, value: Tab) -> some View {
        let isSelected = tab == value
        return Button {
            withAnimation(.spring(duration: 0.24, bounce: 0.14)) {
                tab = value
            }
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        Color.clear
                            .clearGlassSurface(in: Capsule(), interactive: false)
                            .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text(L10n.text("筛选快捷键")))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("需要辅助功能权限才能读取任意应用的菜单快捷键，并在点击时代为执行。"))
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button(L10n.text("授予权限…")) { model.requestPermission() }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 21)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                        .buttonStyle(.plain)
                    Button(L10n.text("重新检查")) { model.refresh() }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 21)
                        .clearGlassSurface(in: Capsule(), interactive: true)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var list: some View {
        let groups = groupedItems
        return ScrollView {
            if groups.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.name) { group in
                        Text(group.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.items) { item in
                            MenuShortcutRow(
                                item: item,
                                isHovered: hoveredID == item.id,
                                isAwaitingConfirmation: model.pendingConfirmationID == item.id,
                                onHover: { hovering in
                                    if hovering { hoveredID = item.id }
                                    else if hoveredID == item.id { hoveredID = nil }
                                },
                                action: { model.perform(item, closePanel: onClose) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.never)
        .frame(height: Self.listHeight)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 6)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button(action: onOpenMain) {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                    Text(L10n.text("打开快捷"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Capsule())
                .clearGlassSurface(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            ClearGlassIconButton(help: L10n.text("设置…"), size: 26, action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }

            ClearGlassIconButton(help: L10n.text("退出"), size: 26) {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11.5, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: Data

    private var usesMenuItems: Bool { model.isTrusted && !model.appItems.isEmpty }

    private var currentItems: [MenuBarShortcutItem] {
        switch tab {
        case .system:
            return model.catalogItems(catalog, scope: .system)
        case .app:
            if usesMenuItems { return model.appItems }
            guard let scope = model.targetScope else { return [] }
            return model.catalogItems(catalog, scope: scope)
        }
    }

    private var groupedItems: [(name: String, items: [MenuBarShortcutItem])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? currentItems : currentItems.filter {
            $0.title.lowercased().contains(needle) || $0.group.lowercased().contains(needle)
                || $0.keys.joined().lowercased().contains(needle)
        }
        var order: [String] = []
        var buckets: [String: [MenuBarShortcutItem]] = [:]
        for item in filtered {
            if buckets[item.group] == nil { order.append(item.group) }
            buckets[item.group, default: []].append(item)
        }
        return order.map { (name: $0, items: buckets[$0] ?? []) }
    }

    private var sourceDescription: String {
        if tab == .system { return L10n.text("QuickKey 收录的系统快捷键") }
        if usesMenuItems { return L10n.format("从菜单栏读取到 {0} 个快捷键", String(model.appItems.count)) }
        if model.targetScope != nil { return L10n.text("QuickKey 收录的快捷键") }
        return L10n.text("授予权限后可读取该应用的全部菜单快捷键")
    }

    private var emptyMessage: String {
        if !query.isEmpty { return L10n.text("没有匹配的快捷键") }
        if model.isLoading { return L10n.text("正在读取菜单…") }
        if tab == .app, !model.isTrusted { return L10n.text("授予权限后可读取该应用的全部菜单快捷键") }
        return L10n.text("这个应用的菜单中没有快捷键")
    }
}

private struct MenuShortcutRow: View {
    let item: MenuBarShortcutItem
    let isHovered: Bool
    let isAwaitingConfirmation: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isAwaitingConfirmation ? L10n.text("再次点击以执行") : item.title)
                    .font(.system(size: 12.5, weight: isHovered ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isAwaitingConfirmation ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                Spacer(minLength: 6)
                if !item.isTriggerable, item.isEnabled {
                    Text(L10n.text("仅展示"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Text(item.keys.joined())
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background {
                if isHovered && item.isTriggerable {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAwaitingConfirmation ? Color.orange.opacity(0.18) : Color.primary.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!item.isTriggerable)
        .opacity(item.isEnabled ? 1 : 0.4)
        .onHover(perform: onHover)
        .help(item.group)
    }
}

private struct ClearGlassIconButton<Label: View>: View {
    let help: String
    var size: CGFloat = 24
    let action: () -> Void
    @ViewBuilder let label: Label
    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .clearGlassSurface(in: Circle(), interactive: true)
                .overlay(Circle().fill(isHovered ? Color.primary.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Liquid Glass helpers with pre-macOS 26 fallback

private extension View {
    @ViewBuilder
    func clearGlassSurface<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.interactive(interactive), in: shape)
        } else {
            self.background(
                shape
                    .fill(Color.primary.opacity(0.08))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            )
        }
    }
}

/// The status bar symbol, larger and crisper than the default system rendering.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        let image = NSImage(systemSymbolName: "command.square", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
