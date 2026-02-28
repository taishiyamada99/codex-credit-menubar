import XCTest
@testable import CodexCreditMenuBar

final class CodexRateLimitServiceParsingTests: XCTestCase {
    func testParseOneLimitUsesPrimaryUsedPercent() async {
        let service = CodexRateLimitService(settings: .default) { _, _, _ in }
        let bucket = await service.parseOneLimit(limitId: "codex", payload: [
            "limitName": "Codex",
            "primary": [
                "usedPercent": 37.5,
                "windowDurationMins": 300
            ]
        ])

        XCTAssertEqual(bucket.limitId, "codex")
        XCTAssertEqual(bucket.usedPercent, 37.5, accuracy: 0.0001)
        XCTAssertEqual(bucket.remainingPercent, 62.5, accuracy: 0.0001)
        XCTAssertEqual(bucket.windowDurationMins, 300)
    }

    func testParseOneLimitSupportsUsedAndLimitCounts() async {
        let service = CodexRateLimitService(settings: .default) { _, _, _ in }
        let bucket = await service.parseOneLimit(limitId: "codex", payload: [
            "primary": [
                "used": 2,
                "limit": 8
            ]
        ])

        XCTAssertEqual(bucket.usedPercent, 25, accuracy: 0.0001)
        XCTAssertEqual(bucket.remainingPercent, 75, accuracy: 0.0001)
    }

    func testParseRateLimitsSupportsSingleObjectResult() async {
        let service = CodexRateLimitService(settings: .default) { _, _, _ in }
        let buckets = await service.parseRateLimits(result: [
            "rateLimits": [
                "limitId": "codex",
                "limitName": "Codex",
                "primary": [
                    "usedPercent": 12
                ]
            ]
        ])

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].limitId, "codex")
        XCTAssertEqual(buckets[0].usedPercent, 12, accuracy: 0.0001)
        XCTAssertEqual(buckets[0].remainingPercent, 88, accuracy: 0.0001)
    }

    func testParseRateLimitsExtractsPrimaryAndSecondaryBuckets() async {
        let service = CodexRateLimitService(settings: .default) { _, _, _ in }
        let buckets = await service.parseRateLimits(result: [
            "rateLimits": [[
                "limitId": "codex",
                "limitName": "Codex",
                "primary": [
                    "usedPercent": 7,
                    "windowDurationMins": 300
                ],
                "secondary": [
                    "usedPercent": 45,
                    "windowDurationMins": 10_080
                ]
            ]]
        ])

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].windowDurationMins, 300)
        XCTAssertEqual(buckets[0].remainingPercent, 93, accuracy: 0.0001)
        XCTAssertEqual(buckets[1].windowDurationMins, 10_080)
        XCTAssertEqual(buckets[1].remainingPercent, 55, accuracy: 0.0001)
    }
}
