import Foundation

/// Persists local user favorites and automatically verified practice completions.
public struct UserLibraryStore: Sendable {
    public static let favoritesKey = "favoriteShortcutIDs"
    public static let practicedKey = "practicedShortcutIDs"

    public private(set) var favorites: Set<String>
    public private(set) var practiced: Set<String>

    public init(favorites: Set<String> = [], practiced: Set<String> = []) {
        self.favorites = favorites
        self.practiced = practiced
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        let favorites = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        let practiced = Set(defaults.stringArray(forKey: practicedKey) ?? [])
        return Self(favorites: favorites, practiced: practiced)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(favorites.sorted(), forKey: Self.favoritesKey)
        defaults.set(practiced.sorted(), forKey: Self.practicedKey)
    }

    public func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    public func isPracticed(_ id: String) -> Bool {
        practiced.contains(id)
    }

    @discardableResult
    public mutating func toggleFavorite(_ id: String) -> Bool {
        if favorites.contains(id) {
            favorites.remove(id)
            return false
        }
        favorites.insert(id)
        return true
    }

    @discardableResult
    public mutating func markPracticed(_ id: String) -> Bool {
        practiced.insert(id).inserted
    }
}
