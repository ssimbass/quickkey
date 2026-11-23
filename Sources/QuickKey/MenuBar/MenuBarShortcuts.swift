import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShortcutCore

/// A shortcut row shown in the menu bar panel, with the way to trigger it.
struct MenuBarShortcutItem: Identifiable, Sendable {
    enum Action: Sendable {
        /// Press the target app's own menu item through Accessibility (most reliable for app shortcuts).
        case pressMenuItem(AXElementBox)
        /// Synthesize the key combination (used for catalog shortcuts such as system ones).
        case sendKeys([String])
        /// Displayed only; the combination cannot be synthesized (e.g. "⌘ 1–8").
        case none
    }

    let id: String
    let title: String
    let group: String
    let keys: [String]
    let isEnabled: Bool
    let action: Action

    var isTriggerable: Bool {
        if case .none = action { return false }
        return isEnabled
    }

    /// Combinations that quit, lock, or delete ask for a second click first.
    var needsConfirmation: Bool {
        guard keys.contains("⌘") else { return false }
        return keys.contains("Q") || keys.contains("⌫") || keys.contains("⌦")
    }
}

/// AXUIElement is a thread-safe CF reference; box it so items can cross actors.
final class AXElementBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

// MARK: - Model

@MainActor
final class MenuBarShortcutModel: ObservableObject {
    @Published private(set) var targetApp: NSRunningApplication?
    @Published private(set) var appItems: [MenuBarShortcutItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var pendingConfirmationID: String?

    private var activationObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var confirmationReset: Task<Void, Never>?

    init() {
        updateTarget(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.updateTarget(app) }
        }
    }

    /// Tracks the last app the user worked in, ignoring QuickKey itself (opening the panel may activate it).
    private func updateTarget(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard app.processIdentifier != targetApp?.processIdentifier else { return }
        targetApp = app
        appItems = []
        refresh()
    }

    var targetScope: AppScope? {
        guard let bundleID = targetApp?.bundleIdentifier else { return nil }
        return AppScope.allCases.first { $0.bundleIdentifier == bundleID }
    }

    func syncFrontmostAndRefresh() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if frontmost.processIdentifier != targetApp?.processIdentifier {
                targetApp = frontmost
                appItems = []
            }
        }
        refresh()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        loadTask?.cancel()
        guard isTrusted, let app = targetApp, !app.isTerminated else {
            isLoading = false
            return
        }
        let pid = app.processIdentifier
        isLoading = true
        loadTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                MenuShortcutReader.read(pid: pid)
            }.value
            guard let self, !Task.isCancelled, self.targetApp?.processIdentifier == pid else { return }
            self.appItems = items
            self.isLoading = false
        }
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func catalogItems(_ catalog: ShortcutCatalog?, scope: AppScope) -> [MenuBarShortcutItem] {
        guard let catalog else { return [] }
        return catalog.shortcuts.filter { $0.scope == scope }.map { shortcut in
            MenuBarShortcutItem(
                id: shortcut.id,
                title: shortcut.title,
                group: shortcut.section,
                keys: shortcut.keys,
                isEnabled: true,
                action: KeyStroke(keys: shortcut.keys) == nil ? .none : .sendKeys(shortcut.keys)
            )
        }
    }

    /// Returns false when the click only armed a confirmation.
    @discardableResult
    func perform(_ item: MenuBarShortcutItem, closePanel: () -> Void) -> Bool {
        guard item.isTriggerable else { return false }
        guard AXIsProcessTrusted() else {
            requestPermission()
            return false
        }
        if item.needsConfirmation, pendingConfirmationID != item.id {
            pendingConfirmationID = item.id
            confirmationReset?.cancel()
            confirmationReset = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.pendingConfirmationID = nil
            }
            return false
        }
        pendingConfirmationID = nil
        closePanel()
        let target = targetApp
        let needsActivation = target?.isActive == false
        if needsActivation {
            target?.activate()
        }
        let delayMs = needsActivation ? 220 : 80
        let action = item.action
        Task.detached(priority: .userInitiated) {
            // Give the window server time to settle focus before delivering the action.
            try? await Task.sleep(for: .milliseconds(delayMs))
            switch action {
            case let .pressMenuItem(box):
                AXUIElementPerformAction(box.element, "AXPress" as CFString)
            case let .sendKeys(keys):
                KeyStroke(keys: keys)?.post()
            case .none:
                break
            }
        }
        return true
    }
}

// MARK: - Reading another app's menu bar

enum MenuShortcutReader {
    static func read(pid: pid_t) -> [MenuBarShortcutItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.5)
        guard let menuBar: AXUIElement = attribute(app, "AXMenuBar"),
              let topItems: [AXUIElement] = attribute(menuBar, "AXChildren") else { return [] }
        var result: [MenuBarShortcutItem] = []
        // Index 0 is the Apple menu, which is the same for every app.
        for top in topItems.dropFirst() {
            let title: String = attribute(top, "AXTitle") ?? ""
            collect(from: top, path: [title], depth: 0, into: &result)
        }
        return result
    }

    private static func collect(from element: AXUIElement, path: [String], depth: Int,
                                into result: inout [MenuBarShortcutItem]) {
        guard depth < 5, let children: [AXUIElement] = attribute(element, "AXChildren") else { return }
        for child in children {
            let role: String = attribute(child, "AXRole") ?? ""
            if role == "AXMenu" {
                collect(from: child, path: path, depth: depth + 1, into: &result)
                continue
            }
            guard role == "AXMenuItem" else { continue }
            let title: String = attribute(child, "AXTitle") ?? ""
            guard !title.isEmpty else { continue }
            if let keys = shortcutKeys(of: child) {
                let enabled: Bool = attribute(child, "AXEnabled") ?? true
                result.append(MenuBarShortcutItem(
                    id: "\(path.joined(separator: "/"))/\(title)/\(keys.joined())/\(result.count)",
                    title: title,
                    group: path.joined(separator: " › "),
                    keys: keys,
                    isEnabled: enabled,
                    action: .pressMenuItem(AXElementBox(child))
                ))
            }
            collect(from: child, path: path + [title], depth: depth + 1, into: &result)
        }
    }

    private static func shortcutKeys(of item: AXUIElement) -> [String]? {
        let glyph = (attribute(item, "AXMenuItemCmdGlyph") as NSNumber?)?.intValue ?? 0
        let character: String? = attribute(item, "AXMenuItemCmdChar")
        let key: String
        if glyph != 0, let name = glyphNames[glyph] {
            key = name
        } else if let character, let scalar = character.unicodeScalars.first, !character.isEmpty {
            if let name = specialCharacters[scalar.value] {
                key = name
            } else if scalar.properties.isWhitespace || scalar.value < 0x20 || (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            } else {
                key = character.uppercased()
            }
        } else {
            return nil
        }
        let modifiers = (attribute(item, "AXMenuItemCmdModifiers") as NSNumber?)?.intValue ?? 0
        var keys: [String] = []
        if modifiers & 0b0100 != 0 { keys.append("⌃") }
        if modifiers & 0b0010 != 0 { keys.append("⌥") }
        if modifiers & 0b0001 != 0 { keys.append("⇧") }
        if modifiers & 0b1000 == 0 { keys.append("⌘") }
        keys.append(key)
        return keys
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Menu glyph codes from Carbon's Menus.h.
    private static let glyphNames: [Int: String] = [
        0x02: "Tab", 0x03: "⇤", 0x04: "⌤", 0x09: "Space", 0x0A: "⌦", 0x0B: "↩", 0x0D: "↩",
        0x17: "⌫", 0x1B: "Esc", 0x1C: "⌧", 0x62: "⇞", 0x64: "←", 0x65: "→", 0x68: "↑", 0x6A: "↓",
        0x6B: "⇟", 0x66: "↖", 0x69: "↘", 0x6F: "F1", 0x70: "F2", 0x71: "F3", 0x72: "F4", 0x73: "F5",
        0x74: "F6", 0x75: "F7", 0x76: "F8", 0x77: "F9", 0x78: "F10", 0x79: "F11", 0x7A: "F12",
        0x87: "F13", 0x88: "F14", 0x89: "F15", 0x8C: "⏏"
    ]

    /// Control characters and NSEvent function-key code points some apps report as the command character.
    private static let specialCharacters: [UInt32: String] = [
        0x08: "⌫", 0x7F: "⌫", 0x09: "Tab", 0x0D: "↩", 0x03: "⌤", 0x1B: "Esc", 0x20: "Space",
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→", 0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘",
        0xF72C: "⇞", 0xF72D: "⇟", 0xF704: "F1", 0xF705: "F2", 0xF706: "F3", 0xF707: "F4", 0xF708: "F5",
        0xF709: "F6", 0xF70A: "F7", 0xF70B: "F8", 0xF70C: "F9", 0xF70D: "F10", 0xF70E: "F11", 0xF70F: "F12"
    ]
}

// MARK: - Synthesizing key combinations

/// One key plus modifiers, parsed from the catalog's key-cap notation (ANSI layout).
struct KeyStroke: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init?(keys: [String]) {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        for key in keys {
            switch key {
            case "⌘": flags.insert(.maskCommand)
            case "⇧": flags.insert(.maskShift)
            case "⌥": flags.insert(.maskAlternate)
            case "⌃": flags.insert(.maskControl)
            default:
                guard code == nil, let mapped = Self.keyCodes[key.uppercased()] else { return nil }
                code = CGKeyCode(mapped)
            }
        }
        guard let code else { return nil }
        self.keyCode = code
        self.flags = flags
    }

    func post() {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.flags.rawValue == rhs.flags.rawValue
    }

    private static let keyCodes: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "`": kVK_ANSI_Grave, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "+": kVK_ANSI_Equal,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        "SPACE": kVK_Space, "TAB": kVK_Tab, "↩": kVK_Return, "ESC": kVK_Escape, "⌫": kVK_Delete,
        "⌦": kVK_ForwardDelete, "←": kVK_LeftArrow, "→": kVK_RightArrow, "↑": kVK_UpArrow, "↓": kVK_DownArrow,
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
        "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12
    ]
}
