import Foundation

/// Keeps the software switcher bounded as new catalog scopes are introduced.
public enum SoftwarePicker {
    public static func visibleIDs(in ids: [String], selectedID: String, slots: Int = 4) -> [String] {
        guard slots > 1, ids.count > slots else { return Array(ids.prefix(max(0, slots))) }
        var visible = Array(ids.prefix(slots - 1))
        if ids.contains(selectedID), !visible.contains(selectedID) {
            visible[visible.count - 1] = selectedID
        }
        return visible
    }

    public static func needsOverflow(_ ids: [String], slots: Int = 4) -> Bool { ids.count > slots }
}
