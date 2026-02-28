import Foundation
import AppKit
import UserNotifications

final class ThresholdNotificationService {
    private let database: AppDatabase
    private var center: UNUserNotificationCenter? {
        // `UNUserNotificationCenter.current()` asserts when running outside an app bundle (e.g. `swift run`).
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    init(database: AppDatabase) {
        self.database = database
    }

    func requestAuthorizationIfNeeded() async {
        guard let center else {
            return
        }
        do {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // no-op
        }
    }

    func evaluate(
        summaries: [BucketSummary],
        thresholds: [Int],
        enabled: Bool,
        languageMode: LanguageMode
    ) async {
        guard enabled else {
            return
        }
        guard center != nil else {
            return
        }

        let sortedThresholds = thresholds.sorted()
        guard !sortedThresholds.isEmpty else {
            return
        }

        for summary in summaries {
            for member in summary.members {
                let remaining = Int(member.remainingPercent.rounded())
                guard let threshold = sortedThresholds.first(where: { remaining <= $0 }) else {
                    continue
                }
                guard let resetAt = member.resetsAt else {
                    continue
                }

                let alreadyNotified = await database.wasThresholdNotified(
                    limitId: member.limitId,
                    resetAt: resetAt,
                    threshold: threshold
                )
                if alreadyNotified {
                    continue
                }

                await sendNotification(
                    for: summary,
                    member: member,
                    threshold: threshold,
                    languageMode: languageMode
                )
                await database.markThresholdNotified(
                    limitId: member.limitId,
                    resetAt: resetAt,
                    threshold: threshold
                )
            }
        }
    }

    private func sendNotification(
        for summary: BucketSummary,
        member: LimitBucket,
        threshold: Int,
        languageMode: LanguageMode
    ) async {
        guard let center else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Codex Credits"
        let body: String
        switch languageMode {
        case .ja:
            body = "\(summary.title) が \(threshold)% 以下です（現在 \(Int(member.remainingPercent.rounded()))%）"
        case .en, .system:
            body = "\(summary.title) is below \(threshold)% (now \(Int(member.remainingPercent.rounded()))%)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "limit-\(member.limitId)-\(threshold)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
