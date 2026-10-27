import Foundation

@main
struct CoreChecks {
    static func main() {
        let checks = CheckRunner()
        let fixtures = makeFixtures()
        func ids(_ query: String, _ scope: AppScope? = nil) -> [String] {
            ShortcutSearch.results(in: fixtures, query: query, scope: scope).map(\.id)
        }

        checks.run("目录加载、来源和教学信息") {
            let catalog = try ShortcutCatalog.load(language: .simplifiedChinese)
            try catalog.validate()
            checks.expect(!catalog.shortcuts.isEmpty, "目录不为空")
            checks.expect(Set(catalog.shortcuts.map(\.scope)) == Set(AppScope.allCases), "包含全部四类目录")
            checks.expect(Set(catalog.shortcuts.map(\.id)).count == catalog.shortcuts.count, "快捷键ID唯一")
            let sourceIDs = Set(catalog.sources.map(\.id))
            let officialHosts = Set(["support.apple.com", "support.google.com", "www.apple.com", "developer.apple.com", "developer.chrome.com"])
            for item in catalog.shortcuts {
                checks.expect(!item.notes.isEmpty, "\(item.id) 有常见问题说明")
                checks.expect(item.steps.count == 3, "\(item.id) 有三步练习")
                checks.expect(!item.sourceIDs.isEmpty && Set(item.sourceIDs).isSubset(of: sourceIDs), "\(item.id) 有有效来源")
                checks.expect(ShortcutSearch.results(in: catalog.shortcuts, query: item.englishKeys).contains(where: { $0.id == item.id }), "\(item.id) 可通过英文按键找到自身")
                checks.expect(ShortcutSearch.results(in: catalog.shortcuts, query: item.keys.joined()).contains(where: { $0.id == item.id }), "\(item.id) 可通过符号按键找到自身")
            }
            for source in catalog.sources {
                checks.expect(source.url.scheme == "https", "来源使用HTTPS")
                checks.expect(officialHosts.contains(source.url.host ?? ""), "来源为官方站点：\(source.url)")
                checks.expect(!source.checkedAt.isEmpty, "来源有核对日期")
            }
            print("  实际目录：\(catalog.shortcuts.count) 个操作；" + AppScope.allCases.map { scope in
                "\(scope.title) \(catalog.shortcuts.filter { $0.scope == scope }.count)"
            }.joined(separator: "，"))
        }

        checks.run("拒绝重复ID、未知来源和不支持的目录版本") {
            let catalog = try ShortcutCatalog.load(language: .simplifiedChinese)
            guard let item = catalog.shortcuts.first else { throw CheckFailure("目录为空") }
            let encoder = JSONEncoder()
            var object = try JSONSerialization.jsonObject(with: encoder.encode(catalog)) as! [String: Any]
            let entry = try JSONSerialization.jsonObject(with: encoder.encode(item))
            object["shortcuts"] = [entry, entry]
            checks.expectThrows("重复ID必须失败") { try decode(object).validate() }
            object["shortcuts"] = [entry]
            object["sources"] = []
            checks.expectThrows("缺失来源必须失败") { try decode(object).validate() }
            object["version"] = 99
            checks.expectThrows("不支持的版本必须失败") { try decode(object).validate() }
        }

        checks.run("空搜索、作用域和稳定顺序") {
            checks.expect(ids("") == fixtures.map(\.id), "空搜索保留原顺序")
            checks.expect(ids("  \n", .finder) == ["folder", "rename"], "空白搜索按作用域")
            checks.expect(ids("⌘L") == ["address", "chrome-address"], "全局搜索匹配多个软件")
            checks.expect(ids("⌘L", .safari) == ["address"], "快捷键按作用域过滤")
            checks.expect(ids("地址栏", .chrome) == ["chrome-address"], "中文按作用域过滤")
            checks.expect(ids("Safari") == ["address", "back", "tab-number"], "按软件名称搜索")
            checks.expect(ids("完全不存在的操作").isEmpty, "无匹配返回空")
        }

        checks.run("中文标题、别名和组合关键词") {
            checks.expect(ids("新建文件夹") == ["folder"], "中文标题")
            checks.expect(ids("创建目录") == ["folder"], "中文别名")
            checks.expect(ids("Finder 新建") == ["folder"], "软件与动作组合")
            checks.expect(ids("sPoTlIgHt") == ["spotlight"], "英文大小写不敏感")
        }

        checks.run("修饰键顺序、Cmd与Ctrl区分、全角输入") {
            for query in ["⌘⇧N", "Command + Shift + N", "shift cmd n", "Shift-Command-N", "⇧ ⌘ n", "⌘＋⇧＋Ｎ"] {
                checks.expect(ids(query) == ["folder"], "等价组合：\(query)")
            }
            checks.expect(ids("Command + N") == ["window"], "不把Cmd+N匹配为Cmd+Shift+N")
            checks.expect(ids("Ctrl + Shift + N") == ["control"], "Ctrl与Command有区别")
            checks.expect(ids("⌃⇧n") == ["control"], "Control符号")
            checks.expect(ids("Ctrl + N").isEmpty, "没有匹配时不回退成Command")
            checks.expect(ids("cmd").contains("folder") && !ids("cmd").contains("control"), "单独修饰键搜索")
            checks.expect(ids("Ｃｍｄ Ｌ") == ["address", "chrome-address"], "全角英文")
        }

        checks.run("Option/Alt、方向键、空格、Return/Esc和标点") {
            for query in ["Alt + Left Arrow", "Option ←", "⌥←", "option 左箭头"] {
                checks.expect(ids(query) == ["word"], "Option与方向键：\(query)")
            }
            for query in ["Command Space", "⌘空格键", "Cmd+Spacebar"] {
                checks.expect(ids(query) == ["spotlight"], "空格键：\(query)")
            }
            for query in ["Return", "回车", "↩", "Enter"] { checks.expect(ids(query) == ["rename"], "Return：\(query)") }
            for query in ["Esc", "Escape", "⎋"] { checks.expect(ids(query) == ["escape"], "Esc：\(query)") }
            checks.expect(ids("⌘[") == ["back"], "方括号键")
            checks.expect(ids("Cmd + +") == ["zoom"], "加号键不作为分隔符丢失")
            checks.expect(ids("+") == ["zoom"], "单独加号只匹配加号键")
            checks.expect(ids("＋") == ["zoom"], "全角加号只匹配加号键")
            checks.expect(ids("Command + Plus") == ["zoom"], "Plus别名")
            checks.expect(ids("Command + 4") == ["tab-number"], "标签页1至8范围")
            checks.expect(ids("Command + 9").isEmpty, "不越过1至8范围")
            checks.expect(ids("Fn + Delete") == ["forward-delete"], "Fn修饰键")
        }

        checks.run("新增软件分类溢出与功能键目录") {
            let four = ["system", "finder", "safari", "chrome"]
            checks.expect(SoftwarePicker.visibleIDs(in: four, selectedID: "chrome") == four, "四分类直接展示")
            checks.expect(!SoftwarePicker.needsOverflow(four), "四分类不需要更多菜单")
            let many = four + ["terminal", "notes", "preview", "mail"]
            checks.expect(SoftwarePicker.needsOverflow(many), "新增分类进入更多菜单")
            checks.expect(SoftwarePicker.visibleIDs(in: many, selectedID: "mail") == ["system", "finder", "mail"], "更多菜单选中分类保持可见")
            checks.expect(SoftwarePicker.visibleIDs(in: many, selectedID: "system").count == 3, "为更多菜单预留固定槽位")
            let catalog = try ShortcutCatalog.load(language: .simplifiedChinese)
            for number in 1...12 {
                let matches = ShortcutSearch.results(in: catalog.shortcuts, query: "F\(number)", scope: .system)
                checks.expect(matches.contains { $0.id == "system-f\(number)" }, "F\(number) 可精确找到")
                checks.expect(matches.allSatisfy { $0.keys.contains("F\(number)") }, "F\(number) 不混淆其他功能键")
            }
            checks.expect(catalog.shortcuts.filter { $0.section == "功能键 F1–F12" }.count == 12, "12个功能键均已收录")
        }

        checks.run("中英文目录完整性、搜索和语言选择") {
            let chinese = try ShortcutCatalog.load(language: .simplifiedChinese)
            let english = try ShortcutCatalog.load(language: .english)
            checks.expect(chinese.shortcuts.map(\.id) == english.shortcuts.map(\.id), "两种语言包含相同且有序的操作")
            checks.expect(chinese.sources.map(\.id) == english.sources.map(\.id), "两种语言引用相同来源")
            for (zh, en) in zip(chinese.shortcuts, english.shortcuts) {
                checks.expect(zh.keys == en.keys && zh.englishKeys == en.englishKeys, "语言不改变按键：\(en.id)")
                checks.expect(zh.practice == en.practice && zh.scope == en.scope && zh.sourceIDs == en.sourceIDs,
                              "语言不改变练习行为和来源：\(en.id)")
                let displayed = [en.title, en.summary, en.section, en.prerequisite, en.expectedResult] + en.steps + en.notes
                checks.expect(displayed.allSatisfy { !$0.isEmpty && $0.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression) == nil },
                              "英文教学文案无漏翻：\(en.id)")
                checks.expect(en.steps.count == 3 && !en.notes.isEmpty, "英文包含完整步骤和提示：\(en.id)")
                checks.expect(ShortcutSearch.results(in: english.shortcuts, query: zh.title).contains { $0.id == en.id },
                              "英文界面可搜中文标题：\(en.id)")
                checks.expect(ShortcutSearch.results(in: chinese.shortcuts, query: en.title).contains { $0.id == zh.id },
                              "中文界面可搜英文标题：\(zh.id)")
            }
            checks.expect(AppLanguage.resolve("system", preferredLanguages: ["en-US", "zh-Hans"]) == .english, "跟随英语系统")
            checks.expect(AppLanguage.resolve("system", preferredLanguages: ["zh-CN", "en"]) == .simplifiedChinese, "跟随中文系统")
            checks.expect(AppLanguage.resolve("en", preferredLanguages: ["zh-Hans"]) == .english, "显式英语优先")
            checks.expect(AppLanguage.resolve("zh-Hans", preferredLanguages: ["en-US"]) == .simplifiedChinese, "显式中文优先")
            checks.expect(AppLanguage.resolve("system", preferredLanguages: ["fr-FR"]) == .english, "不支持的系统语言回退英语")
            checks.expect(L10n.text("练习", language: .english) == "Practice", "英文界面资源加载")
            checks.expect(L10n.text("练习", language: .simplifiedChinese) == "练习", "中文界面文案保留")
            let resources = L10n.resourceBundle
            guard let uiURL = resources.url(forResource: "ui.en", withExtension: "json") else { throw CheckFailure("缺少英文 UI 资源") }
            let strings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: uiURL))
            for (key, value) in strings {
                checks.expect(!value.isEmpty && value.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression) == nil, "英文 UI 无漏翻：\(key)")
                func placeholders(_ text: String) -> [String] {
                    text.components(separatedBy: "{").dropFirst().compactMap { $0.split(separator: "}").first.map(String.init) }.filter { Int($0) != nil }.sorted()
                }
                checks.expect(placeholders(key) == placeholders(value), "插值参数完整：\(key)")
            }
            checks.expect(L10n.format("快捷键 {0} 的教学信息或来源不完整", "{1}").contains("{1}"), "用户文本中的占位符保持原样")
        }

        print("\n核心检查：\(checks.assertions) 个断言，\(checks.groups) 组，\(checks.failures) 处失败。")
        if checks.failures > 0 { exit(1) }
    }

    private static func decode(_ object: [String: Any]) throws -> ShortcutCatalog {
        try JSONDecoder().decode(ShortcutCatalog.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func makeFixtures() -> [Shortcut] {
        func item(_ id: String, _ keys: [String], _ title: String, _ scope: AppScope = .system, _ aliases: [String] = []) -> Shortcut {
            Shortcut(id: id, scope: scope, title: title, keys: keys, englishKeys: keys.joined(separator: " + "), summary: "练习\(title)",
                     section: "常用操作", prerequisite: "准备环境", steps: ["准备", "亲手按键", "观察结果"], expectedResult: "实际效果",
                     aliases: aliases, sourceIDs: ["official"])
        }
        return [
            item("folder", ["⇧", "⌘", "N"], "新建文件夹", .finder, ["创建目录"]),
            item("window", ["⌘", "N"], "新建窗口"), item("control", ["⌃", "⇧", "N"], "Control练习"),
            item("address", ["⌘", "L"], "聚焦地址栏", .safari), item("chrome-address", ["⌘", "L"], "聚焦地址栏", .chrome),
            item("spotlight", ["⌘", "Space"], "打开系统搜索", .system, ["Spotlight"]),
            item("rename", ["↩"], "重命名文件", .finder), item("escape", ["Esc"], "取消操作"),
            item("back", ["⌘", "["], "返回上一页", .safari), item("word", ["⌥", "←"], "移动一个词"),
            item("zoom", ["⌘", "+"], "放大网页", .chrome), item("tab-number", ["⌘", "1…8"], "指定标签页", .safari),
            item("forward-delete", ["Fn", "⌫"], "向前删除字符")
        ]
    }
}

private struct CheckFailure: Error { let message: String; init(_ message: String) { self.message = message } }

private final class CheckRunner {
    var assertions = 0
    var failures = 0
    var groups = 0

    func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        assertions += 1
        if !condition() { failures += 1; print("  FAIL: \(label)") }
    }

    func expectThrows(_ label: String, _ body: () throws -> Void) {
        assertions += 1
        do { try body(); failures += 1; print("  FAIL: \(label)") } catch { }
    }

    func run(_ name: String, _ body: () throws -> Void) {
        groups += 1
        let before = failures
        do { try body() } catch { failures += 1; print("  FAIL: \(error)") }
        print("\(before == failures ? "PASS" : "FAIL"): \(name)")
    }
}
