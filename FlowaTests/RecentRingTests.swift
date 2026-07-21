import XCTest
@testable import Flowa

final class RecentRingTests: XCTestCase {

    func testInsertsNewestFirst() {
        let a = Dictation(text: "first", targetAppName: nil, date: Date(timeIntervalSince1970: 1))
        let b = Dictation(text: "second", targetAppName: "Notes", date: Date(timeIntervalSince1970: 2))
        let one = RecentRing.inserting(a, into: [], limit: 100)
        let two = RecentRing.inserting(b, into: one, limit: 100)
        XCTAssertEqual(two.map(\.text), ["second", "first"])
    }

    func testCapsAtLimit() {
        var items: [Dictation] = []
        for i in 0..<5 {
            let d = Dictation(text: "\(i)", targetAppName: nil, date: Date())
            items = RecentRing.inserting(d, into: items, limit: 3)
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.text), ["4", "3", "2"])
    }
}
