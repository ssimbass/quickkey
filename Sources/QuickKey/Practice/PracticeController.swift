import AppKit
import Combine
import Foundation
import ShortcutCore
import SwiftUI

enum PracticeStatus: Equatable {
    case idle
    case ready(String)
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .idle: L10n.text("准备好环境后，再开始动手练习。")
        case let .ready(message), let .success(message), let .failure(message): message
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

/// Prepares real, isolated practice environments. It never synthesizes keyboard events.
@MainActor
final class PracticeController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var status: PracticeStatus = .idle
    @Published private(set) var isPrepared = false
    @Published private(set) var practiceDirectory: URL?
    @Published private(set) var activeShortcutID: String?
    @Published private(set) var isPreparing = false
    @Published private(set) var hasFloatingHint = false

    private var activeShortcut: Shortcut?
    private var generation = UUID()
    private var monitor: Task<Void, Never>?
    private var practiceWindow: NSWindow?
    private var hintPanel: NSPanel?
    private weak var teachingWindow: NSWindow?
    private var hideObserver: NSObjectProtocol?
    private var suppressWindowEvents = false
    private var sampleURL: URL?
    private var sampleBookmark: Data?
    private var baseline: [FileSnapshot] = []
    private var detectedFileID: UInt64?
    private var lastTrashCheck: Date = .distantPast
    private let opensExternalApplications: Bool

    init(opensExternalApplications: Bool = true) {
        self.opensExternalApplications = opensExternalApplications
        super.init()
    }

    static func automaticallyVerifies(_ shortcut: Shortcut) -> Bool {
        switch shortcut.practice {
        case .newFolder, .renameFile, .duplicateFile, .minimizeWindow, .closeWindow, .hideApp: true
        case .textEditing: TextResultAction.expected(for: shortcut.id) != nil
        default: false
        }
    }

    func prepare(_ shortcut: Shortcut) {
        stop()
        generation = UUID()
        activeShortcut = shortcut
        activeShortcutID = shortcut.id
        teachingWindow = primaryTeachingWindow()
        isPreparing = true

        do {
            switch shortcut.practice {
            case .textEditing:
                isPrepared = true
                status = .ready(L10n.text("等待文本操作。"))
            case .minimizeWindow, .closeWindow, .hideApp:
                preparePracticeWindow(for: shortcut)
            case .newFolder, .renameFile, .duplicateFile, .trashFile, .quickLook, .fileInfo, .openFile:
                try prepareFinder(for: shortcut)
            case .browserAddress, .browserPage:
                try prepareBrowser(for: shortcut)
            case .observation:
                if shortcut.scope == .finder {
                    try prepareFinder(for: shortcut)
                } else if shortcut.scope == .safari || shortcut.scope == .chrome {
                    try prepareBrowser(for: shortcut)
                } else {
                    isPrepared = true
                    status = .ready(L10n.text("观察系统或目标应用的响应。"))
                }
            }
            let opensBrowser = shortcut.practice == .browserAddress || shortcut.practice == .browserPage
                || (shortcut.practice == .observation && (shortcut.scope == .safari || shortcut.scope == .chrome))
            if !opensBrowser {
                isPreparing = false
            }
        } catch {
            isPreparing = false
            isPrepared = false
            status = .failure(L10n.format("准备练习失败：{0}", String(describing: error.localizedDescription)))
        }
    }

    /// Every reset starts a new directory, leaving previous work intact.
    func reset(_ shortcut: Shortcut) { prepare(shortcut) }

    func stop() {
        generation = UUID()
        monitor?.cancel()
        monitor = nil
        if let hideObserver {
            NotificationCenter.default.removeObserver(hideObserver)
            self.hideObserver = nil
        }
        suppressWindowEvents = true
        practiceWindow?.delegate = nil
        practiceWindow?.close()
        practiceWindow = nil
        suppressWindowEvents = false
        hideFloatingHint()
        activeShortcut = nil
        activeShortcutID = nil
        practiceDirectory = nil
        sampleURL = nil
        sampleBookmark = nil
        baseline = []
        detectedFileID = nil
        lastTrashCheck = .distantPast
        isPrepared = false
        isPreparing = false
        status = .idle
    }

    func confirmObservation(_ shortcut: Shortcut) {
        guard activeShortcutID == shortcut.id else {
            status = .failure(L10n.text("请先为当前快捷键准备练习环境。"))
            return
        }
        status = .success(L10n.format("已由你确认「{0}」的实际效果；此结果采用手动确认。", String(describing: shortcut.title)))
    }

    func reportTextResult(_ message: String, success: Bool) {
        guard activeShortcut?.practice == .textEditing else { return }
        guard success || !status.isSuccess else { return }
        status = success ? .success(message) : .ready(message)
    }

    func showFloatingHint(for shortcut: Shortcut, onReturn: @escaping () -> Void) {
        hideFloatingHint()
        if teachingWindow == nil { teachingWindow = primaryTeachingWindow() }
        let panel = HintPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 76),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("QuickKey.FloatingHint")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: FloatingHintView(shortcut: shortcut) { [weak self] in
            guard let self else { return }
            self.hideFloatingHint()
            NSApp.activate(ignoringOtherApps: true)
            self.teachingWindow?.deminiaturize(nil)
            self.teachingWindow?.makeKeyAndOrderFront(nil)
            onReturn()
        })
        let visibleFrame = (teachingWindow?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 18
        ))
        hintPanel = panel
        hasFloatingHint = true
        panel.orderFrontRegardless()
    }

    func hideFloatingHint() {
        hintPanel?.orderOut(nil)
        hintPanel?.close()
        hintPanel = nil
        hasFloatingHint = false
    }

    private func primaryTeachingWindow() -> NSWindow? {
        if let main = NSApp.mainWindow, main !== practiceWindow, main !== hintPanel {
            return main
        }
        return NSApp.windows.first { window in
            window !== practiceWindow && window !== hintPanel && !(window is NSPanel) && window.isVisible
        }
    }

    private func makeSessionDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = support.appendingPathComponent("QuickKey/Practice", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        practiceDirectory = directory
        return directory
    }

    private func prepareFinder(for shortcut: Shortcut) throws {
        let directory = try makeSessionDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(L10n.text("目标文件夹"), isDirectory: true),
            withIntermediateDirectories: false
        )
        let sample = directory.appendingPathComponent(L10n.text("练习笔记.txt"))
        try L10n.text("这是快捷键练习样例。可以在本目录中重命名、制作副本或移到废纸篓。\n原有练习内容会保留，重新准备会新建独立目录。\n")
            .write(to: sample, atomically: true, encoding: .utf8)
        try L10n.text("周末计划\n1. 学会一个常用快捷键\n2. 在真实 Finder 中亲手操作\n")
            .write(to: directory.appendingPathComponent(L10n.text("周末计划.txt")), atomically: true, encoding: .utf8)
        sampleURL = sample
        sampleBookmark = try? sample.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        baseline = try FileSnapshot.read(directory)
        isPrepared = true
        let shouldSelect = shortcut.practice != .newFolder
        if opensExternalApplications {
            if shouldSelect {
                NSWorkspace.shared.activateFileViewerSelecting([sample])
            } else {
                guard NSWorkspace.shared.open(directory) else {
                    throw PracticeError.cannotOpen(L10n.text("Finder 练习目录"))
                }
            }
        }
        switch shortcut.practice {
        case .newFolder:
            status = .ready(L10n.text("等待练习目录出现新文件夹。"))
        case .renameFile:
            status = .ready(L10n.text("等待「练习笔记.txt」名称改变。"))
        case .duplicateFile:
            status = .ready(L10n.text("等待样例文件出现副本。"))
        case .trashFile:
            status = .ready(L10n.text("样例文件已选中。"))
        default:
            status = .ready(L10n.text("练习文件已选中。"))
        }
        if !opensExternalApplications {
            status = .ready(L10n.text("已创建真实练习目录与样例；集成检查模式未启动 Finder，文件监视已就绪。"))
        }
        if [.newFolder, .renameFile, .duplicateFile, .trashFile].contains(shortcut.practice) {
            startDirectoryMonitor(for: shortcut, directory: directory)
        }
    }

    private func startDirectoryMonitor(for shortcut: Shortcut, directory: URL) {
        let session = generation
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                guard let self, self.generation == session else { return }
                do {
                    let current = try FileSnapshot.read(directory)
                    self.inspectChanges(current, for: shortcut)
                } catch {
                    self.status = .failure(L10n.format("练习目录暂时无法读取：{0}。原练习内容已保留，可以重新准备。", String(describing: error.localizedDescription)))
                    return
                }
            }
        }
    }

    private func inspectChanges(_ current: [FileSnapshot], for shortcut: Shortcut) {
        let originalIDs = Set(baseline.map(\.fileID))
        switch shortcut.practice {
        case .newFolder:
            let folders = current.filter { $0.isDirectory && !originalIDs.contains($0.fileID) }
            let target = folders.first(where: { $0.fileID == detectedFileID }) ?? folders.first
            if let target {
                detectedFileID = target.fileID
                status = .success(L10n.format("已在真实练习目录中检测到新文件夹「{0}」。", String(describing: target.name)))
            }
        case .renameFile:
            guard let original = baseline.first(where: { $0.name == sampleURL?.lastPathComponent }),
                  let renamed = current.first(where: { $0.fileID == original.fileID }), renamed.name != original.name else { return }
            status = .success(L10n.format("已检测到样例文件从「{0}」重命名为「{1}」。", String(describing: original.name), String(describing: renamed.name)))
        case .duplicateFile:
            guard let sampleURL, let originalData = try? Data(contentsOf: sampleURL) else { return }
            let addedFiles = current.filter { !$0.isDirectory && !originalIDs.contains($0.fileID) }
            if let duplicate = addedFiles.first(where: { (try? Data(contentsOf: $0.url)) == originalData }) {
                status = .success(L10n.format("已在真实练习目录中检测到内容相同的副本「{0}」。", String(describing: duplicate.name)))
            }
        case .trashFile:
            guard let sampleURL,
                  let original = baseline.first(where: { $0.name == sampleURL.lastPathComponent }),
                  !current.contains(where: { $0.fileID == original.fileID }) else { return }
            // A missing file alone does not prove it was moved to Trash.
            guard Date().timeIntervalSince(lastTrashCheck) > 1.5 else { return }
            lastTrashCheck = Date()
            if let sampleBookmark {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: sampleBookmark,
                                          options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                          bookmarkDataIsStale: &stale),
                   resolved.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) {
                    status = .success(L10n.format("已检测到专用样例文件移入废纸篓。可以在废纸篓中找到「{0}」。", String(describing: resolved.lastPathComponent)))
                    return
                }
            }
            if !status.isSuccess {
                status = .ready(L10n.text("样例文件已离开练习目录；请查看废纸篓。"))
            }
        default: break
        }
    }

    private func preparePracticeWindow(for shortcut: Shortcut) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("QuickKey.PracticeWindow")
        window.title = L10n.text("快捷 · 独立练习窗口")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: PracticeWindowView(shortcut: shortcut))
        window.center()
        practiceWindow = window
        isPrepared = true
        status = .ready(shortcut.practice == .hideApp
            ? L10n.text("练习窗口已打开。隐藏会同时隐藏本应用的教学窗口；点击 Dock 中的“快捷”图标可以返回。")
            : L10n.format("独立练习窗口已打开。请亲手按 {0}，教学主窗口会保留。", String(describing: shortcut.englishKeys)))
        if shortcut.practice == .hideApp {
            let session = generation
            hideObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didHideNotification, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.generation == session else { return }
                    self.status = .success(L10n.text("已检测到“快捷”应用实际隐藏。点击 Dock 中的应用图标即可返回教学页。"))
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard !suppressWindowEvents,
              notification.object as? NSWindow === practiceWindow,
              activeShortcut?.practice == .minimizeWindow else { return }
        status = .success(L10n.text("已检测到独立练习窗口实际最小化。点击 Dock 中的窗口缩略图可以恢复，教学主窗口会保留。"))
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard !suppressWindowEvents,
              notification.object as? NSWindow === practiceWindow,
              activeShortcut?.practice == .minimizeWindow else { return }
        status = .success(L10n.text("已检测到练习窗口从 Dock 恢复。"))
    }

    func windowWillClose(_ notification: Notification) {
        guard !suppressWindowEvents,
              notification.object as? NSWindow === practiceWindow,
              activeShortcut?.practice == .closeWindow else { return }
        status = .success(L10n.text("已检测到独立练习窗口实际关闭，教学主窗口已保留。"))
        let session = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == session else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.teachingWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func prepareBrowser(for shortcut: Shortcut) throws {
        let scope: AppScope = shortcut.scope == .chrome ? .chrome : .safari
        let directory = try makeSessionDirectory()
        let pageURL = directory.appendingPathComponent(L10n.text("快捷键练习.html"))
        try BrowserPracticePage.main.write(to: pageURL, atomically: true, encoding: .utf8)
        try BrowserPracticePage.next.write(to: directory.appendingPathComponent(L10n.text("下一页.html")), atomically: true, encoding: .utf8)
        guard opensExternalApplications else {
            isPreparing = false
            isPrepared = true
            status = .ready(L10n.text("本地练习网页已准备；集成检查模式未启动外部浏览器，也未判断浏览器操作结果。"))
            return
        }
        guard let bundleID = scope.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PracticeError.missingApplication(scope.title)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let session = generation
        NSWorkspace.shared.open([pageURL], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                self.isPreparing = false
                if let error {
                    self.isPrepared = false
                    self.status = .failure(L10n.format("无法打开 {0} 练习网页：{1}", String(describing: scope.title), String(describing: error.localizedDescription)))
                } else {
                    self.isPrepared = true
                    self.status = .ready(L10n.format("练习页已在 {0} 打开。", String(describing: scope.title)))
                }
            }
        }
    }
}

private struct FileSnapshot {
    let name: String
    let url: URL
    let fileID: UInt64
    let isDirectory: Bool

    static func read(_ directory: URL) throws -> [Self] {
        try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .compactMap { url -> Self? in
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard let number = attributes[.systemFileNumber] as? NSNumber else {
                        throw PracticeError.cannotReadFileIdentity
                    }
                    return Self(name: url.lastPathComponent, url: url,
                        fileID: number.uint64Value, isDirectory: attributes[.type] as? FileAttributeType == .typeDirectory)
                } catch {
                    // Finder may rename or move a listed item before its attributes are read.
                    // A vanished entry is part of the next snapshot, not a monitoring failure.
                    if let error = error as? CocoaError,
                       error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                        return nil
                    }
                    let nsError = error as NSError
                    let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                    if (nsError.domain == NSPOSIXErrorDomain && nsError.code == 2)
                        || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == 2) {
                        return nil
                    }
                    throw error
                }
            }
    }
}

private enum PracticeError: LocalizedError {
    case missingApplication(String)
    case cannotOpen(String)
    case cannotReadFileIdentity
    var errorDescription: String? {
        switch self {
        case let .missingApplication(name): L10n.format("没有找到 {0}。请先安装该应用，再准备练习。", String(describing: name))
        case let .cannotOpen(name): L10n.format("无法打开 {0}。练习文件已保留，可点击目录路径手动打开。", String(describing: name))
        case .cannotReadFileIdentity: L10n.text("无法读取练习样例的文件标识。")
        }
    }
}
