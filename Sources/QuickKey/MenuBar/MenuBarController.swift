import AppKit
import SwiftUI
import Combine
import ShortcutCore

/// Borderless non-activating floating panel styled like macOS Control Center.
final class MenuBarFloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: MenuBarPanel.width, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // NSGlassEffectView renders its own rounded SDF shadow on macOS 26+;
        // enabling the window shadow adds rectangular corners from its backdrop layer.
        if #available(macOS 26.0, *) {
            hasShadow = false
        } else {
            hasShadow = true
        }
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Manages the menu bar status item and its clear Liquid Glass floating panel.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: MenuBarFloatingPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var surfaceView: NSView?

    /// Transparent padding around the glass panel on macOS 26+ so NSGlassEffectView's
    /// own rounded shadow renders without clipping at the window boundary.
    private static var shadowInsets: NSEdgeInsets {
        if #available(macOS 26.0, *) {
            return NSEdgeInsets(top: 12, left: 24, bottom: 32, right: 24)
        }
        return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    private var library: LibraryModel?
    private var model: MenuBarShortcutModel?
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    private var isStarted = false
    private var lastAppliedLanguage = AppLanguage.current
    private var cancellables: Set<AnyCancellable> = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var lastAnchorFrame: NSRect?

    func configure(
        library: LibraryModel,
        model: MenuBarShortcutModel,
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.library = library
        self.model = model
        self.openMainWindowAction = openMainWindow
        self.openSettingsAction = openSettings

        guard !QuickKeyAppDelegate.isTestRun else { return }

        if !isStarted {
            isStarted = true
            library.$catalog
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshPanelContent() }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.handleDefaultsChanged() }
                .store(in: &cancellables)
        }

        syncStatusItem()
        refreshPanelContent()
    }

    private func handleDefaultsChanged() {
        syncStatusItem()
        let currentLanguage = AppLanguage.current
        if currentLanguage != lastAppliedLanguage {
            lastAppliedLanguage = currentLanguage
            statusItem?.button?.toolTip = L10n.text("快捷键面板")
            library?.load()
            refreshPanelContent()
        }
    }

    private func syncStatusItem() {
        guard !QuickKeyAppDelegate.isTestRun else { return }
        if MenuBarPreference.isEnabled {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.image = MenuBarIcon.image
                    button.imageScaling = .scaleNone
                    button.toolTip = L10n.text("快捷键面板")
                    button.target = self
                    button.action = #selector(handleStatusItemClick(_:))
                    button.sendAction(on: [.leftMouseDown, .rightMouseDown])
                }
                statusItem = item
            }
        } else {
            closePanel()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let model else { return }
        model.syncFrontmostAndRefresh()

        let panel = ensurePanel()
        refreshPanelContent()

        let anchorFrame = statusItemScreenFrame()
        lastAnchorFrame = anchorFrame
        layoutPanel(panel, anchorFrame: anchorFrame)

        statusItem?.button?.highlight(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.statusItem?.button?.highlight(true)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installDismissMonitors()
    }

    func closePanel() {
        removeDismissMonitors()
        statusItem?.button?.highlight(false)
        panel?.orderOut(nil)
    }

    // MARK: - Panel Construction & Layout

    private func ensurePanel() -> MenuBarFloatingPanel {
        if let panel { return panel }

        let panel = MenuBarFloatingPanel()
        panel.onCancel = { [weak self] in self?.closePanel() }

        let hosting = NSHostingView(rootView: makeRootView())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let container = makeGlassContainer(wrapping: hosting)
        panel.contentView = container

        self.hostingView = hosting
        self.panel = panel
        return panel
    }

    /// Uses macOS 26+ Regular Liquid Glass (matching macOS Control Center's blur,
    /// refraction, and automatic text legibility) inside a transparent shadow-margin host,
    /// with a HUD visual effect fallback on macOS 14–15.
    private func makeGlassContainer(wrapping content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let root = NSView()
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor.clear.cgColor

            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = MenuBarPanel.cornerRadius
            glass.tintColor = nil
            glass.contentView = content
            glass.translatesAutoresizingMaskIntoConstraints = false

            let insets = Self.shadowInsets
            root.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: insets.left),
                glass.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -insets.right),
                glass.topAnchor.constraint(equalTo: root.topAnchor, constant: insets.top),
                glass.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -insets.bottom)
            ])
            self.surfaceView = glass
            return root
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = MenuBarPanel.cornerRadius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
            ])
            self.surfaceView = effect
            return effect
        }
    }

    private func makeRootView() -> AnyView {
        guard let model else { return AnyView(EmptyView()) }
        let language = AppLanguage.current
        return AnyView(
            MenuBarPanel(
                catalog: library?.catalog,
                model: model,
                onClose: { [weak self] in self?.closePanel() },
                onOpenMain: { [weak self] in self?.openMainWindow() },
                onOpenSettings: { [weak self] in self?.openSettingsWindow() },
                onHeightChange: { [weak self] in self?.relayoutIfVisible() }
            )
            .id(language.rawValue)
            .environment(\.locale, Locale(identifier: language.rawValue))
        )
    }

    private func refreshPanelContent() {
        guard let hostingView else { return }
        hostingView.rootView = makeRootView()
        relayoutIfVisible()
    }

    private func relayoutIfVisible() {
        guard let panel, panel.isVisible else { return }
        layoutPanel(panel, anchorFrame: statusItemScreenFrame() ?? lastAnchorFrame)
        panel.invalidateShadow()
    }

    private func statusItemScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(rectInWindow)
    }

    private func layoutPanel(_ panel: MenuBarFloatingPanel, anchorFrame: NSRect?) {
        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let contentWidth = MenuBarPanel.width
        let contentHeight = max(240, min(520, ceil(fitting.height)))
        let insets = Self.shadowInsets

        let screen = screenFor(anchorFrame: anchorFrame) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let margin: CGFloat = 8
        let gapBelowMenuBar: CGFloat = 6

        var visibleX: CGFloat
        var visibleTopY: CGFloat
        if let anchorFrame {
            visibleX = round(anchorFrame.midX - contentWidth / 2)
            visibleTopY = anchorFrame.minY - gapBelowMenuBar
        } else {
            visibleX = visible.maxX - contentWidth - margin
            visibleTopY = visible.maxY - gapBelowMenuBar
        }

        visibleX = min(max(visibleX, visible.minX + margin), visible.maxX - contentWidth - margin)
        let visibleY = max(visible.minY + margin, round(visibleTopY - contentHeight))

        let windowFrame = NSRect(
            x: visibleX - insets.left,
            y: visibleY - insets.bottom,
            width: contentWidth + insets.left + insets.right,
            height: contentHeight + insets.top + insets.bottom
        )
        if panel.frame != windowFrame {
            panel.setFrame(windowFrame, display: true)
        }
    }

    private func screenFor(anchorFrame: NSRect?) -> NSScreen? {
        guard let anchorFrame else { return NSScreen.main }
        let center = NSPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    // MARK: - App Actions

    private func openMainWindow() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: {
            !($0 is MenuBarFloatingPanel)
            && !String(describing: type(of: $0)).contains("StatusBar")
            && $0.canBecomeMain
            && ($0.isVisible || $0.isMiniaturized)
        }) {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }

    private func openSettingsWindow() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Dismiss Monitors

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let targetWindow = event.window
                let isOnStatusItem = targetWindow === self.statusItem?.button?.window
                let isInsideSurface: Bool
                if targetWindow === panel, let surface = self.surfaceView {
                    let point = surface.convert(event.locationInWindow, from: nil)
                    isInsideSurface = surface.bounds.contains(point)
                } else {
                    isInsideSurface = false
                }
                if !isInsideSurface && !isOnStatusItem {
                    self.closePanel()
                }
            }
            return event
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
    }
}
