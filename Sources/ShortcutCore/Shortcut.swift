import Foundation

public enum AppScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, finder, safari, chrome
    public var id: String { rawValue }
    public var title: String {
        switch self { case .system: "系统快捷键"; case .finder: "Finder"; case .safari: "Safari"; case .chrome: "Chrome" }
    }
    public var symbol: String {
        switch self { case .system: "desktopcomputer"; case .finder: "folder"; case .safari: "safari"; case .chrome: "globe" }
    }
    public var bundleIdentifier: String? {
        switch self { case .system: nil; case .finder: "com.apple.finder"; case .safari: "com.apple.Safari"; case .chrome: "com.google.Chrome" }
    }
    public var subtitle: String {
        switch self {
        case .system: "应用切换、文本编辑与窗口操作，从日常最常用的开始。"
        case .finder: "整理文件时，把常用操作交给键盘。"
        case .safari: "地址栏、标签页与阅读，让浏览更顺手。"
        case .chrome: "常用浏览操作，少移动一次鼠标。"
        }
    }
}

public enum PracticeKind: String, Codable, CaseIterable, Sendable {
    case observation, textEditing, newFolder, renameFile, duplicateFile, trashFile
    case quickLook, fileInfo, openFile, minimizeWindow, closeWindow, hideApp
    case browserAddress, browserPage
}

public struct Shortcut: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let scope: AppScope
    public let title: String
    public let keys: [String]
    public let englishKeys: String
    public let summary: String
    public let section: String
    public let prerequisite: String
    public let steps: [String]
    public let expectedResult: String
    public let windowsEquivalent: String?
    public let practice: PracticeKind
    public let notes: [String]
    public let aliases: [String]
    public let sourceIDs: [String]
    public let customizable: Bool

    public init(id: String, scope: AppScope, title: String, keys: [String], englishKeys: String, summary: String,
                section: String, prerequisite: String, steps: [String], expectedResult: String,
                windowsEquivalent: String? = nil, practice: PracticeKind = .observation, notes: [String] = [],
                aliases: [String] = [], sourceIDs: [String], customizable: Bool = false) {
        self.id = id; self.scope = scope; self.title = title; self.keys = keys; self.englishKeys = englishKeys
        self.summary = summary; self.section = section; self.prerequisite = prerequisite; self.steps = steps
        self.expectedResult = expectedResult; self.windowsEquivalent = windowsEquivalent; self.practice = practice
        self.notes = notes; self.aliases = aliases; self.sourceIDs = sourceIDs; self.customizable = customizable
    }
}

public struct ShortcutSource: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let checkedAt: String
}

public struct ShortcutCatalog: Codable, Sendable {
    public let version: Int
    public let verifiedAt: String
    public let sources: [ShortcutSource]
    public let shortcuts: [Shortcut]

    public static func load() throws -> ShortcutCatalog {
        let resourceBundle: Bundle
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("QuickKey_ShortcutCore.bundle"),
           let bundled = Bundle(url: directory) {
            resourceBundle = bundled
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            throw CatalogError.missingResource
        } else {
            resourceBundle = Bundle.module
        }
        guard let url = resourceBundle.url(forResource: "shortcuts", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }

    public func validate() throws {
        guard version == 1 else { throw CatalogError.invalid("不支持的目录版本") }
        guard Set(shortcuts.map(\.id)).count == shortcuts.count else { throw CatalogError.invalid("快捷键 ID 重复") }
        guard Set(sources.map(\.id)).count == sources.count else { throw CatalogError.invalid("来源 ID 重复") }
        let sourceIDs = Set(sources.map(\.id))
        for shortcut in shortcuts {
            guard !shortcut.id.isEmpty, !shortcut.title.isEmpty, !shortcut.keys.isEmpty,
                  !shortcut.englishKeys.isEmpty, !shortcut.summary.isEmpty, !shortcut.section.isEmpty,
                  !shortcut.prerequisite.isEmpty, !shortcut.steps.isEmpty, !shortcut.expectedResult.isEmpty,
                  !shortcut.sourceIDs.isEmpty, Set(shortcut.sourceIDs).isSubset(of: sourceIDs) else {
                throw CatalogError.invalid("快捷键 \(shortcut.id) 的教学信息或来源不完整")
            }
        }
    }
}

public enum CatalogError: LocalizedError {
    case missingResource
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .missingResource: "没有找到快捷键目录文件。"; case let .invalid(message): message }
    }
}
