import AppKit
import Foundation
import ShortcutCore

/// Runs in the actual application process. Checks mutate only generated practice files.
/// No keyboard events are synthesized, and Finder/browsers are never launched here.
@MainActor
enum PracticeIntegrationChecks {
    static func run(catalog: ShortcutCatalog) async throws -> String {
        let controller = PracticeController(opensExternalApplications: false)
        defer { controller.stop() }
        var passed: [String] = []
        let files = FileManager.default

        func item(_ kind: PracticeKind) throws -> Shortcut {
            guard let shortcut = catalog.shortcuts.first(where: { $0.practice == kind }) else {
                throw IntegrationCheckError.failed("目录缺少 \(kind.rawValue) 练习，无法执行检查。")
            }
            return shortcut
        }

        func preparedDirectory(_ shortcut: Shortcut) throws -> URL {
            controller.prepare(shortcut)
            guard controller.isPrepared, let directory = controller.practiceDirectory else {
                throw IntegrationCheckError.failed("准备 \(shortcut.title) 失败：\(controller.status.message)")
            }
            return directory
        }

        let folderShortcut = try item(.newFolder)
        let initialDirectory = try preparedDirectory(folderShortcut)
        try require(files.fileExists(atPath: initialDirectory.appendingPathComponent("目标文件夹").path),
                    "初始目标文件夹未生成。")
        try await Task.sleep(for: .milliseconds(650))
        try require(!controller.status.isSuccess, "初始目标文件夹被误判为用户新建。")
        passed.append("初始样例不误判成功")

        let createdFolder = initialDirectory.appendingPathComponent("集成检查新建文件夹", isDirectory: true)
        try files.createDirectory(at: createdFolder, withIntermediateDirectories: false)
        try await waitUntil("新建文件夹实际反馈") {
            controller.status.isSuccess && controller.status.message.contains(createdFolder.lastPathComponent)
        }
        passed.append("真实新建文件夹反馈")

        let renamedFolder = initialDirectory.appendingPathComponent("集成检查改名后的文件夹", isDirectory: true)
        try files.moveItem(at: createdFolder, to: renamedFolder)
        try await waitUntil("新建文件夹后名称变化反馈") {
            controller.status.isSuccess && controller.status.message.contains(renamedFolder.lastPathComponent)
        }
        passed.append("新文件夹名称持续更新")

        let renameDirectory = try preparedDirectory(item(.renameFile))
        let renamedFile = renameDirectory.appendingPathComponent("集成检查重命名.txt")
        try files.moveItem(at: renameDirectory.appendingPathComponent("练习笔记.txt"), to: renamedFile)
        try await waitUntil("文件重命名实际反馈") {
            controller.status.isSuccess && controller.status.message.contains(renamedFile.lastPathComponent)
        }
        passed.append("真实文件重命名反馈")

        let duplicateDirectory = try preparedDirectory(item(.duplicateFile))
        let duplicate = duplicateDirectory.appendingPathComponent("集成检查副本.txt")
        try files.copyItem(at: duplicateDirectory.appendingPathComponent("练习笔记.txt"), to: duplicate)
        try await waitUntil("文件副本实际反馈") {
            controller.status.isSuccess && controller.status.message.contains(duplicate.lastPathComponent)
        }
        passed.append("真实文件副本反馈")

        let trashDirectory = try preparedDirectory(item(.trashFile))
        let movedFile = trashDirectory.appendingPathComponent("目标文件夹/练习笔记.txt")
        try files.moveItem(at: trashDirectory.appendingPathComponent("练习笔记.txt"), to: movedFile)
        try await waitUntil("移动样例离开顶层目录反馈") {
            controller.status.message.contains("离开练习目录")
        }
        try await Task.sleep(for: .milliseconds(650))
        try require(!controller.status.isSuccess, "移动到普通子目录被误判为移入废纸篓。")
        try require(files.fileExists(atPath: movedFile.path), "移动后的样例未保留。")
        passed.append("普通移动不误判废纸篓")

        let oldDirectory = try preparedDirectory(folderShortcut)
        let keptFile = oldDirectory.appendingPathComponent("重新准备保留检查.txt")
        let keptContents = "重新准备练习必须保留这段内容。"
        try keptContents.write(to: keptFile, atomically: true, encoding: .utf8)
        controller.reset(folderShortcut)
        guard let newDirectory = controller.practiceDirectory else {
            throw IntegrationCheckError.failed("重新准备后没有独立练习目录。")
        }
        try require(oldDirectory != newDirectory, "重新准备复用了旧练习目录。")
        try require(try String(contentsOf: keptFile, encoding: .utf8) == keptContents,
                    "重新准备修改或删除了上次练习的文件。")
        passed.append("重新准备创建新目录并保留原文件")

        try files.createDirectory(at: oldDirectory.appendingPathComponent("旧目录后续变化"), withIntermediateDirectories: false)
        try await Task.sleep(for: .milliseconds(650))
        try require(!controller.status.isSuccess, "旧会话监视仍然影响新会话。")
        passed.append("重新准备取消旧会话监视")

        controller.stop()
        try files.createDirectory(at: newDirectory.appendingPathComponent("停止后的目录变化"), withIntermediateDirectories: false)
        try await Task.sleep(for: .milliseconds(650))
        try require(controller.status == .idle && !controller.isPrepared
                    && controller.activeShortcutID == nil && controller.practiceDirectory == nil,
                    "停止后仍有监视反馈或活动会话状态。")
        try require(files.fileExists(atPath: newDirectory.path), "停止练习删除了练习目录。")
        passed.append("停止释放监视并保留练习目录")

        let minimizeShortcut = try item(.minimizeWindow)
        controller.prepare(minimizeShortcut)
        let minimizingWindow = try practiceWindow()
        minimizingWindow.animationBehavior = .none
        minimizingWindow.miniaturize(nil)
        try await waitUntil("原生窗口最小化事件") {
            minimizingWindow.isMiniaturized && controller.status.isSuccess
        }
        passed.append("真实NSWindow最小化事件")
        minimizingWindow.deminiaturize(nil)
        try await waitUntil("原生窗口恢复事件") {
            !minimizingWindow.isMiniaturized && controller.status.message.contains("恢复")
        }
        passed.append("真实NSWindow恢复事件")

        controller.prepare(try item(.closeWindow))
        let closingWindow = try practiceWindow()
        closingWindow.close()
        try await waitUntil("原生窗口关闭事件") {
            !closingWindow.isVisible && controller.status.isSuccess
        }
        passed.append("真实NSWindow关闭事件")

        // Both active and inactive application states are valid: opening a hint must preserve either.
        try await Task.sleep(for: .milliseconds(200))
        let keyBefore = NSApp.keyWindow
        let activeBefore = NSApp.isActive
        controller.showFloatingHint(for: folderShortcut, onReturn: {})
        try await Task.sleep(for: .milliseconds(200))
        guard let hint = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "QuickKey.FloatingHint" && $0.isVisible
        }) else {
            throw IntegrationCheckError.failed("没有找到真实悬浮提示窗口。")
        }
        try require(NSApp.keyWindow === keyBefore && NSApp.isActive == activeBefore
                    && !hint.canBecomeKey && !hint.canBecomeMain,
                    "悬浮提示条改变了键盘焦点。")
        try require(controller.hasFloatingHint, "悬浮提示条状态没有更新。")
        controller.hideFloatingHint()
        try require(!controller.hasFloatingHint && !hint.isVisible, "悬浮提示条未关闭。")
        passed.append("非激活悬浮提示条保留键盘焦点")

        controller.stop()
        passed.append(contentsOf: try checkNativeTextResults(catalog: catalog))
        return "练习集成检查通过 \(passed.count) 项：\n" + passed.map { "✓ " + $0 }.joined(separator: "\n")
            + "\n检查生成的练习目录均已保留；未启动 Finder 或浏览器，未发送任何键盘事件。"
    }

    private static func checkNativeTextResults(catalog: ShortcutCatalog) throws -> [String] {
        var passed: [String] = []
        var events: [TextResultAction] = []
        let editor = ResultTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 160))
        editor.configure(text: "one two three")
        editor.onResult = { action, _ in events.append(action) }
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "快捷 · 文本操作集成检查"
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: editor.frame)
        scroll.documentView = editor
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        defer { window.close() }

        // Preserve all representations on the clipboard while checking real copy/paste.
        let clipboard = NSPasteboard.general
        let savedClipboard = (clipboard.pasteboardItems ?? []).map { old in
            let saved = NSPasteboardItem()
            for type in old.types {
                if let data = old.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        defer {
            clipboard.clearContents()
            if !savedClipboard.isEmpty { clipboard.writeObjects(savedClipboard) }
        }

        func reset(_ text: String = "one two three", selection: NSRange = NSRange(location: 7, length: 0)) {
            editor.replacePracticeText(text)
            let range = NSRange(location: 0, length: (text as NSString).length)
            editor.setFont(.systemFont(ofSize: 14), range: range)
            editor.textStorage?.removeAttribute(.underlineStyle, range: range)
            editor.setSelectedRange(selection)
            editor.breakUndoCoalescing()
            editor.undoManager?.removeAllActions()
            events.removeAll()
        }
        func reported(_ action: TextResultAction, _ message: String) throws {
            try require(events.contains(action), message)
        }

        reset(selection: NSRange(location: 0, length: 3))
        editor.copy(nil)
        try require(clipboard.string(forType: .string) == "one", "复制未实际写入剪贴板。")
        try reported(.copy, "复制的真实结果没有反馈。")
        passed.append("真实剪贴板复制检测")

        reset("", selection: NSRange(location: 0, length: 0))
        editor.paste(nil)
        try require(editor.string == "one", "粘贴未实际改变文本。")
        try reported(.paste, "粘贴的真实结果没有反馈。")
        passed.append("真实剪贴板粘贴检测")

        reset(selection: NSRange(location: 0, length: 4))
        editor.cut(nil)
        try require(editor.string == "two three" && clipboard.string(forType: .string) == "one ", "剪切的内容或剪贴板结果不正确。")
        try reported(.cut, "剪切的真实结果没有反馈。")
        passed.append("真实文本剪切检测")

        reset()
        editor.selectAll(nil)
        try require(editor.selectedRange() == NSRange(location: 0, length: 13), "全选后的实际选区不正确。")
        try reported(.selectAll, "全选的真实结果没有反馈。")
        passed.append("真实全部选区检测")

        reset("one two", selection: NSRange(location: 7, length: 0))
        editor.insertText(" three", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        guard let undo = editor.undoManager, undo.canUndo else {
            throw IntegrationCheckError.failed("原生文本编辑没有注册撤销操作。")
        }
        undo.undo()
        try require(editor.string == "one two", "撤销未恢复编辑前的文字。")
        try reported(.undo, "撤销的真实结果没有反馈。")
        passed.append("真实文本撤销检测")
        events.removeAll()
        undo.redo()
        try require(editor.string == "one two three", "重做未恢复编辑后的文字。")
        try reported(.redo, "重做的真实结果没有反馈。")
        passed.append("真实文本重做检测")

        let multiline = "one two\nthree four"
        reset(multiline, selection: NSRange(location: 11, length: 0))
        editor.moveToBeginningOfDocument(nil)
        try require(editor.selectedRange() == NSRange(location: 0, length: 0), "光标没有移到文稿开头。")
        try reported(.documentStart, "文稿开头位置没有反馈。")
        passed.append("文稿开头实际位置检测")
        reset(multiline, selection: NSRange(location: 2, length: 0))
        editor.moveToEndOfDocument(nil)
        try require(editor.selectedRange() == NSRange(location: 18, length: 0), "光标没有移到文稿末尾。")
        try reported(.documentEnd, "文稿末尾位置没有反馈。")
        passed.append("文稿末尾实际位置检测")

        reset(multiline, selection: NSRange(location: 11, length: 0))
        editor.moveToLeftEndOfLine(nil)
        try require(editor.selectedRange() == NSRange(location: 8, length: 0), "光标没有移到第二行行首。")
        try reported(.lineStart, "行首实际位置没有反馈。")
        passed.append("行首实际位置检测")
        reset(multiline, selection: NSRange(location: 10, length: 0))
        editor.moveToRightEndOfLine(nil)
        try require(editor.selectedRange() == NSRange(location: 18, length: 0), "光标没有移到第二行行尾。")
        try reported(.lineEnd, "行尾实际位置没有反馈。")
        passed.append("行尾实际位置检测")

        reset(selection: NSRange(location: 7, length: 0))
        editor.moveWordLeft(nil)
        try require(editor.selectedRange() == NSRange(location: 4, length: 0), "向前移动一个词的实际位置不正确。")
        try reported(.previousWord, "向前移动词没有实际反馈。")
        passed.append("向前移动词实际位置检测")
        reset(selection: NSRange(location: 4, length: 0))
        editor.moveWordRight(nil)
        try require(editor.selectedRange() == NSRange(location: 7, length: 0), "向后移动一个词的实际位置不正确。")
        try reported(.nextWord, "向后移动词没有实际反馈。")
        passed.append("向后移动词实际位置检测")

        reset(selection: NSRange(location: 7, length: 0))
        editor.deleteWordBackward(nil)
        try require(editor.string == "one  three", "删除前一个词的实际内容不正确。")
        try reported(.deleteWord, "删除前一个词没有实际反馈。")
        passed.append("删除词实际内容检测")
        reset("one two", selection: NSRange(location: 4, length: 0))
        editor.deleteForward(nil)
        try require(editor.string == "one wo", "向前删除字符的实际内容不正确。")
        try reported(.forwardDelete, "向前删除字符没有实际反馈。")
        passed.append("向前删除实际内容检测")

        reset(multiline, selection: NSRange(location: 10, length: 0))
        editor.moveToRightEndOfLineAndModifySelection(nil)
        try require(editor.selectedRange() == NSRange(location: 10, length: 8), "选中到行尾的实际选区不正确。")
        try reported(.selectToLineEnd, "选中到行尾没有实际反馈。")
        passed.append("选中到行尾实际选区检测")

        for (trait, action, name) in [
            (NSFontTraitMask.boldFontMask, TextResultAction.bold, "粗体"),
            (NSFontTraitMask.italicFontMask, TextResultAction.italic, "斜体")
        ] {
            reset(selection: NSRange(location: 0, length: 3))
            let changedFont = NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: trait)
            editor.setFont(changedFont, range: editor.selectedRange())
            let actualFont = editor.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            try require(actualFont.map { NSFontManager.shared.traits(of: $0).contains(trait) } == true,
                        "选中文字未实际变为\(name)。")
            try reported(action, "\(name)的实际属性变化没有反馈。")
            passed.append("\(name)实际属性变化检测")
        }
        reset(selection: NSRange(location: 0, length: 3))
        editor.underline(nil)
        let underline = editor.attributedString().attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber
        try require((underline?.intValue ?? 0) > 0, "选中文字未实际添加下划线。")
        try reported(.underline, "下划线的实际属性变化没有反馈。")
        passed.append("下划线实际属性变化检测")

        let resultCount = events.count
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        try require(events.count == resultCount, "普通选区变化错误地产生了结果反馈。")
        let textShortcuts = catalog.shortcuts.filter { $0.practice == .textEditing }
        try require(textShortcuts.count == 18 && textShortcuts.allSatisfy { PracticeController.automaticallyVerifies($0) },
                    "自动检测声明没有覆盖已验证的18项文本练习。")
        if let shortcut = textShortcuts.first {
            let controller = PracticeController(opensExternalApplications: false)
            controller.prepare(shortcut)
            controller.reportTextResult("文本已实际改变。", success: true)
            controller.reportTextResult("普通选择变化。", success: false)
            try require(controller.status.isSuccess && controller.status.message == "文本已实际改变。",
                        "成功结果被普通选择变化覆盖。")
            controller.stop()
        }
        passed.append("文本成功结果保留与自动检测范围")
        return passed
    }

    private static func practiceWindow() throws -> NSWindow {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "QuickKey.PracticeWindow" && $0.isVisible
        }) else {
            throw IntegrationCheckError.failed("没有找到真实独立练习窗口。")
        }
        return window
    }

    private static func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        guard condition() else {
            throw IntegrationCheckError.failed("等待\(description)超过3秒。")
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw IntegrationCheckError.failed(message) }
    }
}

private enum IntegrationCheckError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case let .failed(message): message }
    }
}
