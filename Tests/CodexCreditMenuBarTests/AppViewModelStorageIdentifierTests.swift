import Foundation
import XCTest
@testable import CodexCreditMenuBar

final class AppViewModelStorageIdentifierTests: XCTestCase {
    func testStorageIdentifierDiffersAcrossPrimaryAndSecondaryWindows() {
        let primary = LimitBucket(
            limitId: "codex",
            limitName: "codex",
            usedPercent: 8,
            remainingPercent: 92,
            windowDurationMins: 300,
            resetsAt: Date(timeIntervalSince1970: 1_772_626_713),
            updatedAt: Date(timeIntervalSince1970: 1_772_620_000),
            hasSecondary: true
        )
        let secondary = LimitBucket(
            limitId: "codex",
            limitName: "codex",
            usedPercent: 5,
            remainingPercent: 95,
            windowDurationMins: 10_080,
            resetsAt: Date(timeIntervalSince1970: 1_773_117_245),
            updatedAt: Date(timeIntervalSince1970: 1_772_620_000),
            hasSecondary: true
        )

        let primaryID = AppViewModel.storageLimitIdentifier(for: primary)
        let secondaryID = AppViewModel.storageLimitIdentifier(for: secondary)

        XCTAssertNotEqual(primaryID, secondaryID)
    }
}
