import XCTest
@testable import CodexCreditMenuBar

final class ClassificationEngineTests: XCTestCase {
    private let engine = ClassificationEngine()

    func testWindowBasedClassification() {
        let bucket5h = LimitBucket(
            limitId: "a",
            limitName: "a",
            usedPercent: 20,
            remainingPercent: 80,
            windowDurationMins: 300,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        let bucket7d = LimitBucket(
            limitId: "b",
            limitName: "b",
            usedPercent: 20,
            remainingPercent: 80,
            windowDurationMins: 10_080,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )

        XCTAssertEqual(engine.classify(bucket: bucket5h, rules: []), .fiveHour)
        XCTAssertEqual(engine.classify(bucket: bucket7d, rules: []), .sevenDay)
    }

    func testWindowBasedClassificationAllowsNearValues() {
        let near5h = LimitBucket(
            limitId: "a",
            limitName: "a",
            usedPercent: 20,
            remainingPercent: 80,
            windowDurationMins: 299,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        let near7d = LimitBucket(
            limitId: "b",
            limitName: "b",
            usedPercent: 20,
            remainingPercent: 80,
            windowDurationMins: 10_050,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )

        XCTAssertEqual(engine.classify(bucket: near5h, rules: []), .fiveHour)
        XCTAssertEqual(engine.classify(bucket: near7d, rules: []), .sevenDay)
    }

    func testNameBasedClassification() {
        let review = LimitBucket(
            limitId: "review_limit",
            limitName: "Review",
            usedPercent: 40,
            remainingPercent: 60,
            windowDurationMins: nil,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        let spark = LimitBucket(
            limitId: "gpt_spark",
            limitName: "Spark",
            usedPercent: 10,
            remainingPercent: 90,
            windowDurationMins: nil,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )

        XCTAssertEqual(engine.classify(bucket: review, rules: []), .review)
        XCTAssertEqual(engine.classify(bucket: spark, rules: []), .gptSpark)
    }

    func testBengalfoxIdClassifiedAsSpark() {
        let bucket = LimitBucket(
            limitId: "codex_bengalfox",
            limitName: "Internal",
            usedPercent: 1,
            remainingPercent: 99,
            windowDurationMins: nil,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        XCTAssertEqual(engine.classify(bucket: bucket, rules: []), .gptSpark)
    }

    func testAliasRuleOverridesBuiltin() {
        let bucket = LimitBucket(
            limitId: "foo-review",
            limitName: "Review",
            usedPercent: 10,
            remainingPercent: 90,
            windowDurationMins: nil,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        let rule = LimitAliasRule(
            pattern: "foo-review",
            field: .limitId,
            targetKind: .custom,
            enabled: true,
            priority: 1
        )

        XCTAssertEqual(engine.classify(bucket: bucket, rules: [rule]), .custom)
    }

    func testSummariesUseMostConstrainedPrimary() {
        let a = LimitBucket(
            limitId: "a",
            limitName: "a",
            usedPercent: 70,
            remainingPercent: 30,
            windowDurationMins: 10_080,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        let b = LimitBucket(
            limitId: "b",
            limitName: "b",
            usedPercent: 20,
            remainingPercent: 80,
            windowDurationMins: 10_080,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )

        let summaries = engine.summarize(buckets: [a, b], rules: [])
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.kind, .sevenDay)
        XCTAssertEqual(summaries.first?.primary.limitId, "a")
        XCTAssertEqual(summaries.first?.secondary?.limitId, "b")
    }
}
