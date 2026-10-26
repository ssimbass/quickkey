import XCTest
@testable import ShortcutCore

final class ShortcutSearchTests: XCTestCase {
    private func shortcut(_ id: String, scope: AppScope = .system, title: String, keys: [String], english: String,
                          aliases: [String] = []) -> Shortcut {
        Shortcut(id: id, scope: scope, title: title, keys: keys, englishKeys: english, summary: "用于练习\(title)",
                 section: "常用操作", prerequisite: "先准备练习环境", steps: ["准备", "按快捷键", "观察"],
                 expectedResult: "观察真实操作结果", aliases: aliases, sourceIDs: ["official"])
    }

    private var fixtures: [Shortcut] {
        [
            shortcut("folder", scope: .finder, title: "新建文件夹", keys: ["⇧", "⌘", "N"], english: "Shift + Command + N", aliases: ["创建目录"]),
            shortcut("window", title: "新建窗口", keys: ["⌘", "N"], english: "Command + N"),
            shortcut("control", title: "练习 Control", keys: ["⌃", "⇧", "N"], english: "Control + Shift + N"),
            shortcut("address", scope: .safari, title: "聚焦地址栏", keys: ["⌘", "L"], english: "Command + L"),
            shortcut("chrome-address", scope: .chrome, title: "聚焦地址栏", keys: ["⌘", "L"], english: "Command + L"),
            shortcut("spotlight", title: "打开系统搜索", keys: ["⌘", "Space"], english: "Command + Space", aliases: ["Spotlight", "空格"]),
            shortcut("rename", scope: .finder, title: "重命名文件", keys: ["↩"], english: "Return"),
            shortcut("escape", title: "取消操作", keys: ["Esc"], english: "Escape"),
            shortcut("back", scope: .safari, title: "返回上一页", keys: ["⌘", "["], english: "Command + ["),
            shortcut("word", title: "移动一个词", keys: ["⌥", "←"], english: "Option + Left Arrow"),
            shortcut("zoom", scope: .chrome, title: "放大网页", keys: ["⌘", "+"], english: "Command + Plus"),
            shortcut("tab-number", scope: .safari, title: "切换到指定标签页", keys: ["⌘", "1…8"], english: "Command + 1–8")
        ]
    }

    private func ids(_ query: String, scope: AppScope? = nil) -> [String] {
        ShortcutSearch.results(in: fixtures, query: query, scope: scope).map(\.id)
    }

    func testEmptyQueryPreservesOrderAndScope() {
        XCTAssertEqual(ids(""), fixtures.map(\.id))
        XCTAssertEqual(ids("  \n", scope: .finder), ["folder", "rename"])
    }

    func testChineseTitleAndAlias() {
        XCTAssertEqual(ids("新建文件夹"), ["folder"])
        XCTAssertEqual(ids("创建目录"), ["folder"])
        XCTAssertEqual(ids("Finder 新建"), ["folder"])
    }

    func testModifierNamesSymbolsAndOrderAreEquivalent() {
        for query in ["⌘⇧N", "Command + Shift + N", "shift cmd n", "Shift-Command-N", "⇧ ⌘ n"] {
            XCTAssertEqual(ids(query), ["folder"], query)
        }
        XCTAssertEqual(ids("Command + N"), ["window"])
        XCTAssertEqual(ids("Ctrl + Shift + N"), ["control"])
        XCTAssertEqual(ids("⌃⇧n"), ["control"])
        XCTAssertFalse(ids("Ctrl + N").contains("window"))
    }

    func testOptionAliasesAndArrowNames() {
        for query in ["Alt + Left Arrow", "Option ←", "⌥←", "option 左箭头"] {
            XCTAssertEqual(ids(query), ["word"], query)
        }
    }

    func testSpecialKeysAndPunctuation() {
        for query in ["Command Space", "⌘空格键", "Cmd+Spacebar"] { XCTAssertEqual(ids(query), ["spotlight"]) }
        for query in ["Return", "回车", "↩", "Enter"] { XCTAssertEqual(ids(query), ["rename"]) }
        for query in ["Esc", "Escape", "⎋"] { XCTAssertEqual(ids(query), ["escape"]) }
        XCTAssertEqual(ids("⌘["), ["back"])
        XCTAssertEqual(ids("Cmd + +"), ["zoom"])
        XCTAssertEqual(ids("+"), ["zoom"])
        XCTAssertEqual(ids("＋"), ["zoom"])
        XCTAssertEqual(ids("Command + Plus"), ["zoom"])
        XCTAssertEqual(ids("Command + 4"), ["tab-number"])
        XCTAssertEqual(ids("Command + 9"), [])
    }

    func testEveryCatalogEntryCanBeFoundByItsDisplayedKeys() throws {
        let catalog = try ShortcutCatalog.load()
        for item in catalog.shortcuts {
            XCTAssertTrue(ShortcutSearch.results(in: catalog.shortcuts, query: item.englishKeys).contains(where: { $0.id == item.id }), item.id + " 英文按键无法找到自身")
            XCTAssertTrue(ShortcutSearch.results(in: catalog.shortcuts, query: item.keys.joined()).contains(where: { $0.id == item.id }), item.id + " 符号按键无法找到自身")
        }
    }

    func testAppScopeAndGlobalSearch() {
        XCTAssertEqual(ids("⌘L"), ["address", "chrome-address"])
        XCTAssertEqual(ids("⌘L", scope: .safari), ["address"])
        XCTAssertEqual(ids("地址栏", scope: .chrome), ["chrome-address"])
        XCTAssertEqual(ids("Safari"), ["address", "back", "tab-number"])
        XCTAssertEqual(ids("不存在的快捷键"), [])
    }

    func testModifierOnlyQueryAndCaseFolding() {
        XCTAssertTrue(ids("cmd").contains("folder"))
        XCTAssertFalse(ids("cmd").contains("control"))
        XCTAssertEqual(ids("sPoTlIgHt"), ["spotlight"])
        XCTAssertEqual(ids("Ｃｍｄ Ｌ"), ["address", "chrome-address"])
    }
}
