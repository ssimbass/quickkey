import XCTest
@testable import ShortcutCore

final class ShortcutCatalogTests: XCTestCase {
    func testBundledCatalogIsCompleteAndUsesOfficialSources() throws {
        let catalog = try ShortcutCatalog.load()
        try catalog.validate()
        XCTAssertFalse(catalog.shortcuts.isEmpty)
        XCTAssertEqual(Set(catalog.shortcuts.map(\.scope)), Set(AppScope.allCases))
        XCTAssertEqual(Set(catalog.shortcuts.map(\.id)).count, catalog.shortcuts.count)
        for item in catalog.shortcuts {
            XCTAssertFalse(item.notes.isEmpty, item.id + " 缺少常见问题")
            XCTAssertEqual(item.steps.count, 3, item.id + " 应包含三步练习")
        }
        let allowedHosts = Set(["support.apple.com", "support.google.com", "www.apple.com", "developer.apple.com", "developer.chrome.com"])
        for source in catalog.sources {
            XCTAssertEqual(source.url.scheme, "https")
            XCTAssertTrue(allowedHosts.contains(source.url.host ?? ""), source.url.absoluteString)
            XCTAssertFalse(source.checkedAt.isEmpty)
        }
    }

    func testValidationRejectsDuplicateIDsAndMissingSources() throws {
        let catalog = try ShortcutCatalog.load()
        let item = try XCTUnwrap(catalog.shortcuts.first)
        let encoder = JSONEncoder()
        let baseData = try encoder.encode(catalog)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: baseData) as? [String: Any])
        let encodedItem = try JSONSerialization.jsonObject(with: encoder.encode(item))
        object["shortcuts"] = [encodedItem, encodedItem]
        let duplicate = try JSONDecoder().decode(ShortcutCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try duplicate.validate())
        object["shortcuts"] = [encodedItem]
        object["sources"] = []
        let missingSource = try JSONDecoder().decode(ShortcutCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try missingSource.validate())
    }
}
