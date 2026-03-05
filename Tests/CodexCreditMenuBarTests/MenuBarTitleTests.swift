import XCTest
@testable import CodexCreditMenuBar

final class MenuBarTitleTests: XCTestCase {
    func testBuildMenuBarTitleUsesOnlyAvailableKinds() {
        let settings = testSettings(visibleKinds: [.review, .fiveHour, .sevenDay])
        let summaries = [makeSummary(kind: .sevenDay, remaining: 88)]

        let title = AppViewModel.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .ok
        )

        XCTAssertEqual(title, "7D88%")
    }

    func testBuildMenuBarTitleUsesAuthAndStatusWhenNoData() {
        let settings = testSettings(visibleKinds: [.sevenDay])

        let authTitle = AppViewModel.buildMenuBarTitle(
            summaries: [],
            settings: settings,
            serviceState: ServiceState(
                sourceLabel: "-",
                status: .ok,
                lastUpdatedAt: nil,
                buckets: [],
                message: nil,
                authRequired: true
            ),
            effectiveStatus: .ok
        )
        XCTAssertEqual(authTitle, "AUTH")

        let loadingTitle = AppViewModel.buildMenuBarTitle(
            summaries: [],
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .loading
        )
        XCTAssertEqual(loadingTitle, "...")
    }

    func testBuildMenuBarTitleShowsPercent() {
        let settings = testSettings(visibleKinds: [.fiveHour])
        let summaries = [makeSummary(kind: .fiveHour, remaining: 64)]

        let title = AppViewModel.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .ok
        )

        XCTAssertEqual(title, "5H64%")
    }

    func testBuildMenuBarTitleAlwaysUsesThreeInlineItems() {
        let settings = testSettings(visibleKinds: [.sevenDay, .fiveHour, .gptSpark, .review])
        let summaries = [
            makeSummary(kind: .sevenDay, remaining: 88),
            makeSummary(kind: .fiveHour, remaining: 64),
            makeSummary(kind: .gptSpark, remaining: 55),
            makeSummary(kind: .review, remaining: 40)
        ]

        let title = AppViewModel.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .ok
        )

        XCTAssertEqual(title, "7D88% 5H64% SP55% +1")
    }

    private func testSettings(
        visibleKinds: [BucketKind]
    ) -> AppSettings {
        var settings = AppSettings.default
        settings.visibleKinds = visibleKinds
        return settings
    }

    private func makeSummary(kind: BucketKind, remaining: Double) -> BucketSummary {
        let bucket = LimitBucket(
            limitId: "\(kind.rawValue)-id",
            limitName: "\(kind.rawValue)-name",
            usedPercent: 100 - remaining,
            remainingPercent: remaining,
            windowDurationMins: nil,
            resetsAt: nil,
            updatedAt: nil,
            hasSecondary: false
        )
        return BucketSummary(
            id: kind.rawValue,
            kind: kind,
            title: kind.rawValue,
            shortLabel: kind.shortLabel,
            primary: bucket,
            secondary: nil,
            members: [bucket]
        )
    }
}
