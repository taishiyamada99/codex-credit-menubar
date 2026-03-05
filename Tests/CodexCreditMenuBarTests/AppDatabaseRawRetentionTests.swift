import Foundation
import XCTest
@testable import CodexCreditMenuBar

final class AppDatabaseRawRetentionTests: XCTestCase {
    func testShortRawAggregationUsesMinimumRemaining() async {
        let db = await makeDatabase()
        let slot: Int64 = 1_700_000_100
        let captured = Date(timeIntervalSince1970: TimeInterval(slot))
        let samples = [
            RawBucketSample(
                limitId: "codex_weekly_a",
                limitName: "Codex Weekly A",
                kind: .sevenDay,
                remainingPercent: 80,
                usedPercent: 20,
                resetsAt: nil,
                source: .exact
            ),
            RawBucketSample(
                limitId: "codex_weekly_b",
                limitName: "Codex Weekly B",
                kind: .sevenDay,
                remainingPercent: 30,
                usedPercent: 70,
                resetsAt: nil,
                source: .exact
            )
        ]

        await db.saveShortRawSamples(slotEpoch: slot, capturedAt: captured, samples: samples)
        let points = await db.fetchShortRawHistory(fromSlotEpoch: slot, kinds: [.sevenDay])

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.remainingPercent ?? -1, 30, accuracy: 0.0001)
    }

    func testLongTermPruneHonorsRetention() async {
        let db = await makeDatabase()

        let oldSample = RawBucketSample(
            limitId: "codex_weekly_a",
            limitName: "Codex Weekly A",
            kind: .sevenDay,
            remainingPercent: 70,
            usedPercent: 30,
            resetsAt: nil,
            source: .exact
        )
        let recentSample = RawBucketSample(
            limitId: "codex_weekly_a",
            limitName: "Codex Weekly A",
            kind: .sevenDay,
            remainingPercent: 60,
            usedPercent: 40,
            resetsAt: nil,
            source: .exact
        )

        await db.saveLongTermRawDaily(
            dayKeyGMT: "2024-01-01",
            capturedAt: Date(timeIntervalSince1970: 1_704_067_200),
            samples: [oldSample]
        )
        await db.saveLongTermRawDaily(
            dayKeyGMT: "2026-03-03",
            capturedAt: Date(timeIntervalSince1970: 1_772_496_000),
            samples: [recentSample]
        )

        let now = Date(timeIntervalSince1970: 1_772_582_400) // 2026-03-04T00:00:00Z
        await db.pruneLongTermRawDaily(retention: .oneYear, now: now)

        let points = await db.fetchLongTermRawHistory(fromDayKeyGMT: "2020-01-01", kinds: [.sevenDay])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.dateLocal, "2026-03-03")
    }

    func testShortRawKeepsBothFiveHourAndSevenDayFromSameBaseLimit() async {
        let db = await makeDatabase()
        let slot: Int64 = 1_772_626_700
        let captured = Date(timeIntervalSince1970: TimeInterval(slot))

        let primaryBucket = LimitBucket(
            limitId: "codex",
            limitName: "codex",
            usedPercent: 8,
            remainingPercent: 92,
            windowDurationMins: 300,
            resetsAt: Date(timeIntervalSince1970: 1_772_626_713),
            updatedAt: Date(timeIntervalSince1970: 1_772_626_700),
            hasSecondary: true
        )
        let secondaryBucket = LimitBucket(
            limitId: "codex",
            limitName: "codex",
            usedPercent: 5,
            remainingPercent: 95,
            windowDurationMins: 10_080,
            resetsAt: Date(timeIntervalSince1970: 1_773_117_245),
            updatedAt: Date(timeIntervalSince1970: 1_772_626_700),
            hasSecondary: true
        )

        let samples = [
            RawBucketSample(
                limitId: AppViewModel.storageLimitIdentifier(for: primaryBucket),
                limitName: "codex",
                kind: .fiveHour,
                remainingPercent: 92,
                usedPercent: 8,
                resetsAt: primaryBucket.resetsAt,
                source: .exact
            ),
            RawBucketSample(
                limitId: AppViewModel.storageLimitIdentifier(for: secondaryBucket),
                limitName: "codex",
                kind: .sevenDay,
                remainingPercent: 95,
                usedPercent: 5,
                resetsAt: secondaryBucket.resetsAt,
                source: .exact
            )
        ]

        await db.saveShortRawSamples(slotEpoch: slot, capturedAt: captured, samples: samples)
        let points = await db.fetchShortRawHistory(fromSlotEpoch: slot, kinds: [.fiveHour, .sevenDay])

        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points.contains(where: { $0.kind == .fiveHour && abs($0.remainingPercent - 92) < 0.0001 }))
        XCTAssertTrue(points.contains(where: { $0.kind == .sevenDay && abs($0.remainingPercent - 95) < 0.0001 }))
    }

    private func makeDatabase() async -> AppDatabase {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = directory.appendingPathComponent("test.sqlite")
        return AppDatabase(databaseURL: dbURL)
    }
}
