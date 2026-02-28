import XCTest
@testable import CodexCreditMenuBar

final class MenuBarTitleTests: XCTestCase {
    func testBuildMenuBarTitleUsesOnlyAvailableKinds() {
        let settings = testSettings(
            visibleKinds: [.review, .fiveHour, .sevenDay],
            inlineMaxCount: 2,
            privacyMode: false
        )
        let summaries = [makeSummary(kind: .sevenDay, remaining: 88)]

        let title = AppViewModel.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .ok,
            privacyMask: "••"
        )

        XCTAssertEqual(title, "7D 88%")
    }

    func testBuildMenuBarTitleUsesAuthAndStatusWhenNoData() {
        let settings = testSettings(visibleKinds: [.sevenDay], inlineMaxCount: 2, privacyMode: false)

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
            effectiveStatus: .ok,
            privacyMask: "••"
        )
        XCTAssertEqual(authTitle, "AUTH")

        let loadingTitle = AppViewModel.buildMenuBarTitle(
            summaries: [],
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .loading,
            privacyMask: "••"
        )
        XCTAssertEqual(loadingTitle, "...")
    }

    func testBuildMenuBarTitleAppliesPrivacyMask() {
        let settings = testSettings(
            visibleKinds: [.fiveHour],
            inlineMaxCount: 2,
            privacyMode: true
        )
        let summaries = [makeSummary(kind: .fiveHour, remaining: 64)]

        let title = AppViewModel.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: .initial,
            effectiveStatus: .ok,
            privacyMask: "••"
        )

        XCTAssertEqual(title, "5H ••")
    }

    private func testSettings(
        visibleKinds: [BucketKind],
        inlineMaxCount: Int,
        privacyMode: Bool
    ) -> AppSettings {
        var settings = AppSettings.default
        settings.visibleKinds = visibleKinds
        settings.inlineMaxCount = inlineMaxCount
        settings.privacyMode = privacyMode
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
