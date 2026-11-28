import Foundation
import ShortcutCore

/// Centralizes per-shortcut practice recipes and environment metadata so views stay declarative.
enum PracticeConfiguration {
    struct TextPracticeRecipe {
        let expectedAction: TextResultAction
        let sample: String
        let hint: String
        let hasPasteTarget: Bool
        let selectsSample: Bool
        let initialSelection: NSRange
    }

    static let usesExistingBrowserContext: Set<String> = [
        "safari-reader", "safari-add-reading-list", "safari-homepage", "safari-settings",
        "safari-reading-list", "safari-bookmarks-sidebar", "safari-downloads",
        "safari-private-window", "safari-history",
        "chrome-settings", "chrome-incognito", "chrome-history", "chrome-downloads",
        "chrome-bookmark-manager", "chrome-bookmarks-bar",
        "chrome-search-tabs", "chrome-minimize-window", "chrome-clear-browsing-data", "chrome-switch-profile"
    ]

    static let preparationHintIDs: Set<String> = [
        "finder-rename", "finder-new-folder", "finder-move-copied",
        "safari-next-tab", "safari-previous-tab", "safari-last-tab", "safari-numbered-tab", "safari-tab-overview",
        "chrome-next-tab", "chrome-previous-tab", "chrome-last-tab", "chrome-numbered-tab",
        "safari-back", "chrome-back", "safari-forward", "chrome-forward",
        "safari-reopen-tab", "chrome-reopen-tab"
    ]

    static let textActionByShortcutID: [String: TextResultAction] = [
        "system-copy": .copy,
        "system-paste": .paste,
        "system-cut": .cut,
        "system-select-all": .selectAll,
        "system-undo": .undo,
        "system-redo": .redo,
        "system-document-start": .documentStart,
        "system-document-end": .documentEnd,
        "system-line-start": .lineStart,
        "system-line-end": .lineEnd,
        "system-previous-word": .previousWord,
        "system-next-word": .nextWord,
        "system-delete-word": .deleteWord,
        "system-forward-delete": .forwardDelete,
        "system-select-to-line-end": .selectToLineEnd,
        "system-bold": .bold,
        "system-italic": .italic,
        "system-underline": .underline
    ]

    /// All shortcut IDs explicitly referenced by practice configuration, verified against the catalog in checks.
    static var referencedShortcutIDs: Set<String> {
        usesExistingBrowserContext
            .union(preparationHintIDs)
            .union(textActionByShortcutID.keys)
    }

    @MainActor
    static func needsEnvironment(for shortcut: Shortcut) -> Bool {
        guard shortcut.practice != .textEditing else { return false }
        if [.safari, .chrome].contains(shortcut.scope) {
            return !usesExistingBrowserContext.contains(shortcut.id)
        }
        return PracticeController.automaticallyVerifies(shortcut)
            || shortcut.scope == .finder
            || shortcut.practice == .trashFile
    }

    static func preparationHint(for shortcutID: String) -> String? {
        switch shortcutID {
        case "finder-rename":
            L10n.text("按 Return，输入新名称，再按 Return 确认。")
        case "finder-new-folder":
            L10n.text("在练习目录中创建文件夹，输入名称后按 Return。")
        case "finder-move-copied":
            L10n.text("先复制样例文件，再打开“目标文件夹”进行移动。")
        case "safari-next-tab", "safari-previous-tab", "safari-last-tab", "safari-numbered-tab", "safari-tab-overview",
             "chrome-next-tab", "chrome-previous-tab", "chrome-last-tab", "chrome-numbered-tab":
            L10n.text("打开练习页后，再按 ⌘ T 新建一个标签页。")
        case "safari-back", "chrome-back":
            L10n.text("先点击练习页中的“下一页”，再尝试后退。")
        case "safari-forward", "chrome-forward":
            L10n.text("先进入练习“下一页”并后退一次，再尝试前进。")
        case "safari-reopen-tab", "chrome-reopen-tab":
            L10n.text("先关闭工具打开的样例标签页，再尝试恢复。")
        default:
            nil
        }
    }

    static func textRecipe(for shortcutID: String) -> TextPracticeRecipe? {
        guard let action = textActionByShortcutID[shortcutID] else { return nil }
        let sample = textSample(for: shortcutID)
        let selectsSample = ["system-copy", "system-cut", "system-bold", "system-italic", "system-underline"].contains(shortcutID)
        let hasPasteTarget = ["system-copy", "system-paste"].contains(shortcutID)
        let nsSample = sample as NSString
        let initialSelection: NSRange
        if selectsSample {
            initialSelection = NSRange(location: 0, length: min(AppLanguage.current == .english ? 13 : 8, nsSample.length))
        } else if ["system-previous-word", "system-next-word", "system-delete-word"].contains(shortcutID) {
            initialSelection = NSRange(location: min(13, nsSample.length), length: 0)
        } else {
            initialSelection = NSRange(location: nsSample.length / 2, length: 0)
        }
        return TextPracticeRecipe(
            expectedAction: action,
            sample: sample,
            hint: textHint(for: shortcutID),
            hasPasteTarget: hasPasteTarget,
            selectsSample: selectsSample,
            initialSelection: initialSelection
        )
    }

    private static func textSample(for id: String) -> String {
        switch id {
        case "system-previous-word", "system-next-word", "system-delete-word":
            "Mac shortcuts make work easier."
        case "system-document-start", "system-document-end", "system-line-start", "system-line-end", "system-select-to-line-end":
            L10n.text("先把光标放在这里。\n再试试移动到开头或末尾。")
        default:
            L10n.text("把快捷键，用在真正的操作里。")
        }
    }

    private static func textHint(for id: String) -> String {
        switch id {
        case "system-copy": L10n.text("复制选中的文字，再在下方粘贴查看。")
        case "system-paste": L10n.text("先复制上方文字，再在下方粘贴。")
        case "system-undo": L10n.text("先改动文字，再撤销。")
        case "system-redo": L10n.text("先改动文字并撤销，再重做。")
        case "system-bold", "system-italic", "system-underline": L10n.text("对选中的文字使用快捷键。")
        case "system-delete-word", "system-forward-delete": L10n.text("将光标放在文字中间后操作。")
        default: L10n.text("点击文本放置光标，再使用快捷键。")
        }
    }
}
