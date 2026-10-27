import AppKit
import ShortcutCore
import SwiftUI

struct NativeTextPractice: View {
    let shortcut: Shortcut
    let onResult: (String, Bool) -> Void
    @ViewState private var source: String
    @ViewState private var target: String

    init(shortcut: Shortcut, onResult: @escaping (String, Bool) -> Void) {
        self.shortcut = shortcut
        self.onResult = onResult
        _source = ViewState(initialValue: Self.sample(for: shortcut.id))
        _target = ViewState(initialValue: "")
    }

    private static func sample(for id: String) -> String {
        switch id {
        case "system-previous-word", "system-next-word", "system-delete-word": "Mac shortcuts make work easier."
        case "system-document-start", "system-document-end", "system-line-start", "system-line-end", "system-select-to-line-end":
            L10n.text("先把光标放在这里。\n再试试移动到开头或末尾。")
        default: L10n.text("把快捷键，用在真正的操作里。")
        }
    }

    private var hasPasteTarget: Bool { ["system-copy", "system-paste"].contains(shortcut.id) }
    private var selectsSample: Bool {
        ["system-copy", "system-cut", "system-bold", "system-italic", "system-underline"].contains(shortcut.id)
    }
    private var sourceSelection: NSRange {
        let sample = Self.sample(for: shortcut.id) as NSString
        if selectsSample { return NSRange(location: 0, length: min(AppLanguage.current == .english ? 13 : 8, sample.length)) }
        if ["system-previous-word", "system-next-word", "system-delete-word"].contains(shortcut.id) {
            return NSRange(location: min(13, sample.length), length: 0)
        }
        return NSRange(location: sample.length / 2, length: 0)
    }
    private var hint: String {
        switch shortcut.id {
        case "system-copy": L10n.text("复制选中的文字，再在下方粘贴查看。")
        case "system-paste": L10n.text("先复制上方文字，再在下方粘贴。")
        case "system-undo": L10n.text("先改动文字，再撤销。")
        case "system-redo": L10n.text("先改动文字并撤销，再重做。")
        case "system-bold", "system-italic", "system-underline": L10n.text("对选中的文字使用快捷键。")
        case "system-delete-word", "system-forward-delete": L10n.text("将光标放在文字中间后操作。")
        default: L10n.text("点击文本放置光标，再使用快捷键。")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
            PracticeTextEditor(text: $source, initialSelection: sourceSelection, label: L10n.text("练习文本"), onResult: report)
                .frame(height: 75)
                .id(shortcut.id + "-source")
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.14)))
            if hasPasteTarget {
                PracticeTextEditor(text: $target, initialSelection: NSRange(location: 0, length: 0), label: L10n.text("粘贴区域"), onResult: report)
                    .frame(height: 53)
                    .id(shortcut.id + "-target")
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.14)))
            }
        }
        .onChange(of: shortcut.id) { _, _ in source = Self.sample(for: shortcut.id); target = "" }
    }

    private func report(_ action: TextResultAction, _ detail: String) {
        guard action == TextResultAction.expected(for: shortcut.id) else { return }
        onResult(detail, true)
    }
}

enum TextResultAction: Equatable {
    case copy, paste, cut, selectAll, undo, redo, changed
    case documentStart, documentEnd, lineStart, lineEnd, previousWord, nextWord
    case deleteWord, forwardDelete, selectToLineEnd, bold, italic, underline

    static func expected(for shortcutID: String) -> Self? {
        switch shortcutID {
        case "system-copy": .copy
        case "system-paste": .paste
        case "system-cut": .cut
        case "system-select-all": .selectAll
        case "system-undo": .undo
        case "system-redo": .redo
        case "system-document-start": .documentStart
        case "system-document-end": .documentEnd
        case "system-line-start": .lineStart
        case "system-line-end": .lineEnd
        case "system-previous-word": .previousWord
        case "system-next-word": .nextWord
        case "system-delete-word": .deleteWord
        case "system-forward-delete": .forwardDelete
        case "system-select-to-line-end": .selectToLineEnd
        case "system-bold": .bold
        case "system-italic": .italic
        case "system-underline": .underline
        default: nil
        }
    }
}

struct PracticeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let initialSelection: NSRange
    let label: String
    let onResult: (TextResultAction, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ResultTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 75))
        editor.configure(text: text)
        editor.setAccessibilityLabel(label)
        editor.onResult = onResult
        editor.onTextChange = { [weak coordinator = context.coordinator] value in coordinator?.parent.text = value }
        let length = (text as NSString).length
        let location = min(initialSelection.location, length)
        editor.setSelectedRange(NSRange(location: location, length: min(initialSelection.length, length - location)))
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ResultTextView else { return }
        editor.onResult = onResult
        if editor.string != text { editor.replacePracticeText(text) }
    }

    final class Coordinator {
        var parent: PracticeTextEditor
        init(_ parent: PracticeTextEditor) { self.parent = parent }
    }
}

/// Calls AppKit first, then verifies native selection, storage or clipboard results.
@MainActor
final class ResultTextView: NSTextView, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    var onResult: ((TextResultAction, String) -> Void)?
    var onTextChange: ((String) -> Void)?
    private var performingCommand = false
    private var previousText = ""
    private var attributedSnapshot = NSAttributedString(string: "")

    func configure(text: String) {
        isEditable = true
        isSelectable = true
        isRichText = true
        allowsUndo = true
        font = .systemFont(ofSize: 14)
        textColor = .textColor
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: 9, height: 10)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        string = text
        previousText = String(decoding: text.utf8, as: UTF8.self)
        attributedSnapshot = NSAttributedString(attributedString: attributedString())
        delegate = self
        textStorage?.delegate = self
    }

    func replacePracticeText(_ text: String) {
        textStorage?.delegate = nil
        string = text
        previousText = String(decoding: text.utf8, as: UTF8.self)
        attributedSnapshot = NSAttributedString(attributedString: attributedString())
        textStorage?.delegate = self
    }

    func textDidChange(_ notification: Notification) {
        let changed = previousText != string
        previousText = String(decoding: string.utf8, as: UTF8.self)
        onTextChange?(string)
        guard changed, !performingCommand else { return }
        if undoManager?.isUndoing == true {
            onResult?(.undo, L10n.text("文本已撤销。"))
        } else if undoManager?.isRedoing == true {
            onResult?(.redo, L10n.text("文本已重做。"))
        }
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        let current = NSAttributedString(attributedString: textStorage)
        let previous = attributedSnapshot
        attributedSnapshot = current
        if !current.isEqual(to: previous) {
            if undoManager?.isUndoing == true {
                onResult?(.undo, L10n.text("文本已撤销。"))
            } else if undoManager?.isRedoing == true {
                onResult?(.redo, L10n.text("文本已重做。"))
            }
        }
        let range = selectedRange()
        guard editedMask.contains(.editedAttributes), previous.string == current.string,
              range.length > 0, NSMaxRange(range) <= current.length, NSMaxRange(range) <= previous.length else { return }
        for (trait, action, message) in [
            (NSFontTraitMask.boldFontMask, TextResultAction.bold, L10n.text("选中文字已设为粗体。")),
            (NSFontTraitMask.italicFontMask, TextResultAction.italic, L10n.text("选中文字已设为斜体。"))
        ] {
            if allCharacters(in: current, range: range, have: trait)
                && !allCharacters(in: previous, range: range, have: trait) {
                onResult?(action, message)
            }
        }
        if allUnderlined(current, range: range) && !allUnderlined(previous, range: range) {
            onResult?(.underline, L10n.text("选中文字已添加下划线。"))
        }
    }

    private func allCharacters(in text: NSAttributedString, range: NSRange, have trait: NSFontTraitMask) -> Bool {
        var matches = true
        text.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let font = value as? NSFont, NSFontManager.shared.traits(of: font).contains(trait) else {
                matches = false; return
            }
        }
        return matches
    }

    private func allUnderlined(_ text: NSAttributedString, range: NSRange) -> Bool {
        var matches = true
        text.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            if (value as? NSNumber)?.intValue ?? 0 == 0 { matches = false }
        }
        return matches
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { super.copy(sender); return }
        let selected = (string as NSString).substring(with: range)
        let clipboardVersion = NSPasteboard.general.changeCount
        super.copy(sender)
        if NSPasteboard.general.changeCount != clipboardVersion,
           NSPasteboard.general.string(forType: .string) == selected {
            onResult?(.copy, L10n.text("选中文字已复制到剪贴板。"))
        }
    }

    override func cut(_ sender: Any?) {
        let previous = NSString(string: string)
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= previous.length else { super.cut(sender); return }
        let selected = previous.substring(with: range)
        let clipboardVersion = NSPasteboard.general.changeCount
        performingCommand = true
        super.cut(sender)
        performingCommand = false
        if string == previous.replacingCharacters(in: range, with: ""),
           NSPasteboard.general.changeCount != clipboardVersion,
           NSPasteboard.general.string(forType: .string) == selected {
            onResult?(.cut, L10n.text("选中文字已剪切到剪贴板。"))
        }
    }

    override func paste(_ sender: Any?) { performPaste { super.paste(sender) } }
    override func pasteAsPlainText(_ sender: Any?) { performPaste { super.pasteAsPlainText(sender) } }
    override func pasteAsRichText(_ sender: Any?) { performPaste { super.pasteAsRichText(sender) } }

    private func performPaste(_ operation: () -> Void) {
        let previous = string
        performingCommand = true
        operation()
        performingCommand = false
        if string != previous { onResult?(.paste, L10n.text("剪贴板内容已粘贴到文本框。")) }
    }

    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        if !string.isEmpty, selectedRange() == NSRange(location: 0, length: (string as NSString).length) {
            onResult?(.selectAll, L10n.text("已选中全部文字。"))
        }
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        let before = selectedRange(); super.moveToBeginningOfDocument(sender)
        reportMovement(before: before, target: 0, action: .documentStart, message: L10n.text("光标已移到文稿开头。"))
    }
    override func moveToEndOfDocument(_ sender: Any?) {
        let before = selectedRange(); super.moveToEndOfDocument(sender)
        reportMovement(before: before, target: (string as NSString).length, action: .documentEnd, message: L10n.text("光标已移到文稿末尾。"))
    }
    override func moveToBeginningOfLine(_ sender: Any?) {
        let before = selectedRange(), target = visualLineRange().location; super.moveToBeginningOfLine(sender)
        reportMovement(before: before, target: target, action: .lineStart, message: L10n.text("光标已移到行首。"))
    }
    override func moveToLeftEndOfLine(_ sender: Any?) {
        let before = selectedRange(), target = visualLineRange().location; super.moveToLeftEndOfLine(sender)
        reportMovement(before: before, target: target, action: .lineStart, message: L10n.text("光标已移到行首。"))
    }
    override func moveToEndOfLine(_ sender: Any?) {
        let before = selectedRange(), target = NSMaxRange(visualLineRange()); super.moveToEndOfLine(sender)
        reportMovement(before: before, target: target, action: .lineEnd, message: L10n.text("光标已移到行尾。"))
    }
    override func moveToRightEndOfLine(_ sender: Any?) {
        let before = selectedRange(), target = NSMaxRange(visualLineRange()); super.moveToRightEndOfLine(sender)
        reportMovement(before: before, target: target, action: .lineEnd, message: L10n.text("光标已移到行尾。"))
    }
    override func moveWordLeft(_ sender: Any?) {
        let before = selectedRange(); super.moveWordLeft(sender); reportWordMovement(before: before, forward: false)
    }
    override func moveWordBackward(_ sender: Any?) {
        let before = selectedRange(); super.moveWordBackward(sender); reportWordMovement(before: before, forward: false)
    }
    override func moveWordRight(_ sender: Any?) {
        let before = selectedRange(); super.moveWordRight(sender); reportWordMovement(before: before, forward: true)
    }
    override func moveWordForward(_ sender: Any?) {
        let before = selectedRange(); super.moveWordForward(sender); reportWordMovement(before: before, forward: true)
    }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) {
        let before = selectedRange(), end = NSMaxRange(visualLineRange())
        super.moveToEndOfLineAndModifySelection(sender); reportLineSelection(before: before, end: end)
    }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) {
        let before = selectedRange(), end = NSMaxRange(visualLineRange())
        super.moveToRightEndOfLineAndModifySelection(sender); reportLineSelection(before: before, end: end)
    }
    override func deleteWordBackward(_ sender: Any?) {
        let previous = NSString(string: string), before = selectedRange()
        super.deleteWordBackward(sender)
        let removed = previous.length - (string as NSString).length, after = selectedRange()
        if before.length == 0, removed > 0, after.length == 0,
           after.location + removed == before.location,
           previous.replacingCharacters(in: NSRange(location: after.location, length: removed), with: "") == string {
            onResult?(.deleteWord, L10n.text("光标前的词已删除。"))
        }
    }
    override func deleteForward(_ sender: Any?) {
        let previous = NSString(string: string), before = selectedRange()
        super.deleteForward(sender)
        guard before.length == 0, before.location < previous.length else { return }
        let character = previous.rangeOfComposedCharacterSequence(at: before.location)
        if selectedRange() == before, previous.replacingCharacters(in: character, with: "") == string {
            onResult?(.forwardDelete, L10n.text("光标后的字符已删除。"))
        }
    }

    private func reportMovement(before: NSRange, target: Int, action: TextResultAction, message: String) {
        if selectedRange() != before, selectedRange() == NSRange(location: target, length: 0) { onResult?(action, message) }
    }
    private func reportWordMovement(before: NSRange, forward: Bool) {
        let after = selectedRange()
        guard before.length == 0, after.length == 0,
              forward ? after.location > before.location : after.location < before.location else { return }
        onResult?(forward ? .nextWord : .previousWord, forward ? L10n.text("光标已向后移动一个词。") : L10n.text("光标已向前移动一个词。"))
    }
    private func reportLineSelection(before: NSRange, end: Int) {
        guard before.length == 0, end > before.location,
              selectedRange() == NSRange(location: before.location, length: end - before.location) else { return }
        onResult?(.selectToLineEnd, L10n.text("已选中光标到行尾的文字。"))
    }
    private func visualLineRange() -> NSRange {
        let text = string as NSString, position = min(selectedRange().location, text.length)
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        if position == text.length, text.character(at: text.length - 1) == 10 {
            return NSRange(location: position, length: 0)
        }
        guard let manager = layoutManager, let container = textContainer else {
            return text.lineRange(for: NSRange(location: position, length: 0))
        }
        manager.ensureLayout(for: container)
        let glyph = manager.glyphIndexForCharacter(at: min(position, text.length - 1))
        var glyphRange = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphRange)
        var range = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        while range.length > 0, [10, 13].contains(text.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
        return range
    }
}
