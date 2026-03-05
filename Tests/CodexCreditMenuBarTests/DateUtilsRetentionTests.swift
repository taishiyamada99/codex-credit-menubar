import XCTest
@testable import CodexCreditMenuBar

final class DateUtilsRetentionTests: XCTestCase {
    func testFiveMinuteSlotEpochRoundsDown() {
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        let slot = DateUtils.fiveMinuteSlotEpoch(from: date)
        XCTAssertEqual(slot % 300, 0)
        XCTAssertEqual(slot, 1_700_000_100)
    }

    func testNextFiveMinuteBoundary() {
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        let next = DateUtils.nextFiveMinuteBoundary(from: date)
        XCTAssertEqual(next.timeIntervalSince1970, 1_700_000_400, accuracy: 0.0001)
    }

    func testNextGMTMidnightUsesFixedGMT() {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: "2026-03-04T23:30:00Z") else {
            XCTFail("invalid fixture")
            return
        }
        let next = DateUtils.nextGMTMidnight(from: date)
        guard let expected = formatter.date(from: "2026-03-05T00:00:00Z") else {
            XCTFail("invalid expected fixture")
            return
        }
        XCTAssertEqual(next.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.5)
    }

    func testGMTDateKey() {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: "2026-03-04T00:30:00Z") else {
            XCTFail("invalid fixture")
            return
        }
        XCTAssertEqual(DateUtils.gmtDateKey(from: date), "2026-03-04")
    }
}
