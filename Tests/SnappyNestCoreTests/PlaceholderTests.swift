import XCTest
@testable import SnappyNestCore

final class PlaceholderTests: XCTestCase {
    func testVersionTagIsNotEmpty() {
        XCTAssertFalse(SnappyNestCore.versionTag.isEmpty)
    }
}
