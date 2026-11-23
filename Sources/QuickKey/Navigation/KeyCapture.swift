import AppKit
import Carbon.HIToolbox

/// Captures a single in-app key combination without requesting Accessibility or global monitoring.
@MainActor
final class KeyCaptureSession: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    func toggle(onCapture: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            start(onCapture: onCapture)
        }
    }

    func start(onCapture: @escaping (String) -> Void) {
        stop()
        isRecording = true
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
            if event.keyCode == UInt16(kVK_Escape), relevantModifiers.isEmpty {
                self.stop()
                return nil
            }
            if let formatted = Self.format(event: event) {
                self.stop()
                onCapture(formatted)
                return nil
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        isRecording = false
    }

    static func format(event: NSEvent) -> String? {
        guard let key = keyToken(for: event) else { return nil }
        var parts: [String] = []
        let flags = event.modifierFlags
        let isFunctionKey = key.hasPrefix("F") && Int(key.dropFirst()) != nil
        let isArrowOrNav = ["←", "→", "↑", "↓", "⌦", "⇞", "⇟", "↖", "↘"].contains(key)
        if flags.contains(.function) && !isFunctionKey && !isArrowOrNav { parts.append("Fn") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(key)
        return parts.joined(separator: " ")
    }

    private static func keyToken(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            guard let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
                  chars.count == 1 else { return nil }
            let upper = chars.uppercased()
            if upper == "=" && event.modifierFlags.contains(.shift) { return "+" }
            return upper
        }
    }
}
