import XCTest
@testable import SnappyNestCore

final class ZoneTabLocatorTests: XCTestCase {
    private let sample = """
    # tz zone descriptions
    #
    #country-\tcoordinates\tTZ\tcomments
    SG\t+0117+10351\tAsia/Singapore
    GB\t+513030-0000731\tEurope/London
    AU\t-3352+15113\tAustralia/Sydney\tNew South Wales (most areas)
    US\t+340308-1181434\tAmerica/Los_Angeles\tPacific
    XX\tgarbage\tBad/Row
    """

    func testParsesMinutesForm() {
        let t = ZoneTabLocator.parse(sample)
        let sg = t["Asia/Singapore"]!
        XCTAssertEqual(sg.latitude, 1 + 17.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(sg.longitude, 103 + 51.0 / 60, accuracy: 1e-9)
    }

    func testParsesSecondsFormAndNegativeLongitude() {
        let t = ZoneTabLocator.parse(sample)
        let london = t["Europe/London"]!
        XCTAssertEqual(london.latitude, 51 + 30.0 / 60 + 30.0 / 3600, accuracy: 1e-9)
        XCTAssertEqual(london.longitude, -(0 + 7.0 / 60 + 31.0 / 3600), accuracy: 1e-9)
        let la = t["America/Los_Angeles"]!
        XCTAssertEqual(la.longitude, -(118 + 14.0 / 60 + 34.0 / 3600), accuracy: 1e-9)
    }

    func testParsesSouthernHemisphere() {
        let sydney = ZoneTabLocator.parse(sample)["Australia/Sydney"]!
        XCTAssertEqual(sydney.latitude, -(33 + 52.0 / 60), accuracy: 1e-9)
        XCTAssertEqual(sydney.longitude, 151 + 13.0 / 60, accuracy: 1e-9)
    }

    func testSkipsCommentsAndMalformedRows() {
        let t = ZoneTabLocator.parse(sample)
        XCTAssertEqual(t.count, 4)
        XCTAssertNil(t["Bad/Row"])
        XCTAssertNil(t["GMT+8"])
    }

    func testMissingFileYieldsNil() {
        let url = URL(fileURLWithPath: "/nonexistent/zone.tab")
        XCTAssertNil(ZoneTabLocator.coordinates(for: "Asia/Singapore", zoneTab: url))
    }

    func testSystemZoneTabResolvesSingapore() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: ZoneTabLocator.defaultURL.path))
        let sg = ZoneTabLocator.coordinates(for: "Asia/Singapore")
        XCTAssertEqual(sg?.latitude ?? 0, 1.2833, accuracy: 0.01)
        XCTAssertEqual(sg?.longitude ?? 0, 103.85, accuracy: 0.01)
        XCTAssertNil(ZoneTabLocator.coordinates(for: "GMT+8"))
    }
}
