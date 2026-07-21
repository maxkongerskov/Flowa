import XCTest
@testable import Flowa

final class LanguageOptionTests: XCTestCase {

    func testDisplayNameForKnownCode() {
        XCTAssertEqual(LanguageOption.displayName(for: "en"), "English")
        XCTAssertEqual(LanguageOption.displayName(for: "da"), "Danish")
        XCTAssertEqual(LanguageOption.displayName(for: "auto"), "Auto-detect")
    }

    func testDisplayNameFallsBackToCode() {
        XCTAssertEqual(LanguageOption.displayName(for: "zz-unknown"), "zz-unknown")
    }

    func testFilteredByDisplayName() {
        let matches = LanguageOption.filtered(query: "dani")
        XCTAssertTrue(matches.contains(where: { $0.code == "da" }))
    }

    func testFilteredByCodePrefix() {
        let matches = LanguageOption.filtered(query: "da")
        XCTAssertTrue(matches.contains(where: { $0.code == "da" }))
    }

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(LanguageOption.filtered(query: "").count, LanguageOption.all.count)
        XCTAssertGreaterThan(LanguageOption.all.count, 90)
    }
}
