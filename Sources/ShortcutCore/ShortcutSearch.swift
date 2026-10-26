import Foundation

/// Searches a catalog without changing its display order or recording a user's queries.
public enum ShortcutSearch {
    public static func results(in shortcuts: [Shortcut], query: String, scope: AppScope? = nil) -> [Shortcut] {
        let candidates = shortcuts.filter { scope == nil || $0.scope == scope }
        let query = folded(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }

        if let combination = KeyQuery(query) {
            return candidates.filter { combination.matches($0.keys) }
        }

        let terms = query.split(whereSeparator: { $0.isWhitespace || $0 == "+" || $0 == "＋" })
            .map { compact(String($0)) }.filter { !$0.isEmpty }
        return candidates.filter { shortcut in
            let fields = [shortcut.title, shortcut.summary, shortcut.section, shortcut.scope.title,
                          shortcut.scope.rawValue, shortcut.englishKeys, shortcut.keys.joined()] + shortcut.aliases
            let text = compact(fields.joined(separator: " "))
            return terms.allSatisfy(text.contains)
        }
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func compact(_ value: String) -> String {
        folded(value).filter { !$0.isWhitespace }
    }

    private struct KeyQuery {
        let modifiers: Set<String>
        let keys: [String]

        init?(_ query: String) {
            var remainder = query
            var found = Set<String>()
            for (name, pattern) in Self.modifierPatterns {
                let range = remainder.range(of: pattern, options: .regularExpression)
                if range != nil {
                    found.insert(name)
                    remainder = remainder.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
                }
            }

            // A plus between keys is a separator; a second plus is the '+' key itself.
            let plusCount = remainder.filter { $0 == "+" || $0 == "＋" }.count
            remainder = remainder.replacingOccurrences(of: "+", with: " ")
                .replacingOccurrences(of: "＋", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder != "-" {
                remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "-–— "))
            }
            var base: [String] = []
            if remainder.isEmpty {
                if plusCount >= 2 || (plusCount == 1 && found.isEmpty) { base = ["+"] }
            } else if let key = Self.key(remainder) {
                base = [key]
            } else {
                return nil
            }

            guard !found.isEmpty || !base.isEmpty else { return nil }
            self.modifiers = found
            self.keys = base
        }

        func matches(_ symbols: [String]) -> Bool {
            var candidateModifiers = Set<String>()
            var candidateKeys: [String] = []
            for symbol in symbols {
                let normalized = folded(symbol).trimmingCharacters(in: .whitespacesAndNewlines)
                if let modifier = Self.modifierPatterns.first(where: {
                    normalized.range(of: "^(?:\($0.1))$", options: .regularExpression) != nil
                }) {
                    candidateModifiers.insert(modifier.0)
                } else if let key = Self.key(normalized) {
                    candidateKeys.append(key)
                }
            }

            if keys.isEmpty { return modifiers.isSubset(of: candidateModifiers) }
            if !modifiers.isEmpty && modifiers != candidateModifiers { return false }
            return keys.allSatisfy { wanted in
                candidateKeys.contains { candidate in
                    if wanted == candidate { return true }
                    if candidate == "1...8", let number = Int(wanted) { return (1...8).contains(number) }
                    return false
                }
            }
        }

        private static let modifierPatterns: [(String, String)] = [
            ("command", #"\b(?:command|cmd)\b|⌘"#),
            ("shift", #"\bshift\b|⇧"#),
            ("option", #"\b(?:option|alt)\b|⌥"#),
            ("control", #"\b(?:control|ctrl)\b|⌃"#),
            ("fn", #"\bfn\b|🌐"#)
        ]

        private static func key(_ value: String) -> String? {
            let value = compact(value)
            switch value {
            case "space", "spacebar", "空格", "空格键", "␣": return "space"
            case "return", "enter", "回车", "回车键", "↩", "↵", "⌤": return "return"
            case "escape", "esc", "⎋": return "escape"
            case "tab", "⇥", "制表键": return "tab"
            case "delete", "backspace", "⌫", "删除键": return "delete"
            case "forwarddelete", "⌦": return "forwarddelete"
            case "left", "leftarrow", "←", "左箭头": return "left"
            case "right", "rightarrow", "→", "右箭头": return "right"
            case "up", "uparrow", "↑", "上箭头": return "up"
            case "down", "downarrow", "↓", "下箭头": return "down"
            case "pageup", "⇞": return "pageup"
            case "pagedown", "⇟": return "pagedown"
            case "home", "↖": return "home"
            case "end", "↘": return "end"
            case "1…8", "1–8", "1-8", "1...8", "1至8": return "1...8"
            case "plus", "加号": return "+"
            case "+", "-", "=", "[", "]", "\\", "/", ".", ",", "`", ";", "'": return value
            default:
                if value.count == 1, let scalar = value.unicodeScalars.first,
                   CharacterSet.alphanumerics.contains(scalar), scalar.isASCII { return value }
                if value.range(of: #"^f(?:[1-9]|1[0-9]|2[0-4])$"#, options: .regularExpression) != nil { return value }
                return nil
            }
        }
    }
}
