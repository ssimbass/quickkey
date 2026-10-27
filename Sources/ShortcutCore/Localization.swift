import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static func resolve(_ preference: String, preferredLanguages: [String]) -> Self {
        if let explicit = Self(rawValue: preference), explicit != .system { return explicit }
        for language in preferredLanguages {
            if language.hasPrefix("zh") { return .simplifiedChinese }
            if language.hasPrefix("en") { return .english }
        }
        return .english
    }

    public static var current: Self {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1),
           let language = Self(rawValue: arguments[index + 1]), language != .system {
            return language
        }
        return resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system",
                       preferredLanguages: Locale.preferredLanguages)
    }
}

public enum L10n {
    static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("QuickKey_ShortcutCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }

    private static let english: [String: String] = {
        guard let url = resourceBundle.url(forResource: "ui.en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String: String].self, from: data) else {
            preconditionFailure("Missing English interface translations")
        }
        return strings
    }()

    public static func text(_ key: String, language: AppLanguage = .current) -> String {
        let resolved = language == .system ? AppLanguage.current : language
        return resolved == .english ? english[key] ?? key : key
    }

    public static func format(_ key: String, _ arguments: String...) -> String {
        // Split before substitution so user-supplied text containing markers stays literal.
        let template = text(key)
        return template.components(separatedBy: "{").enumerated().map { index, part in
            guard index > 0 else { return part }
            guard let end = part.firstIndex(of: "}"), let number = Int(part[..<end]),
                  arguments.indices.contains(number) else { return "{" + part }
            return arguments[number] + part[part.index(after: end)...]
        }.joined()
    }
}
