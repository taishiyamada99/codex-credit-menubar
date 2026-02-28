import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var serviceState: ServiceState
    @Published var summaries: [BucketSummary]
    @Published var diagnostics: [DiagnosticEvent]
    @Published var historyPoints: [SnapshotPoint]
    @Published var historyRangeDays: Int
    @Published var historyKinds: Set<BucketKind>

    private let classification = ClassificationEngine()
    private let database: AppDatabase
    private let notifier: ThresholdNotificationService
    private let service: CodexRateLimitService
    private let startAtLoginManager = StartAtLoginManager()

    private var streamTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?

    init() {
        let db = AppDatabase()
        self.database = db
        self.notifier = ThresholdNotificationService(database: db)
        self.settings = .default
        self.serviceState = .initial
        self.summaries = []
        self.diagnostics = []
        self.historyPoints = []
        self.historyRangeDays = 30
        self.historyKinds = Set(BucketKind.allCases)

        self.service = CodexRateLimitService(settings: .default) { [db] level, code, message in
            Task {
                await db.appendDiagnostic(level: level, code: code, message: message)
            }
        }

        bootstrap()
    }

    deinit {
        streamTask?.cancel()
        snapshotTask?.cancel()
        let service = service
        Task {
            await service.stop()
        }
    }

    var visibleSummariesForMenu: [BucketSummary] {
        let selectedKinds = Set(settings.visibleKinds)
        let filtered = summaries.filter { selectedKinds.contains($0.kind) }
        if filtered.isEmpty {
            if let sevenDay = summaries.first(where: { $0.kind == .sevenDay }) {
                return [sevenDay]
            }
            if let first = summaries.first {
                return [first]
            }
        }
        return filtered
    }

    var healthText: String {
        switch effectiveStatus {
        case .ok:
            return localized(.healthOk)
        case .loading:
            return localized(.healthLoading)
        case .stale:
            return localized(.healthStale)
        case .error:
            return localized(.healthError)
        }
    }

    var effectiveStatus: AppHealthStatus {
        if serviceState.status == .ok && DateUtils.isStale(lastUpdated: serviceState.lastUpdatedAt, thresholdMinutes: 15) {
            return .stale
        }
        return serviceState.status
    }

    func localized(_ key: L10nKey) -> String {
        L10n.text(key, languageMode: settings.languageMode)
    }

    func sourceModeTitle(_ mode: SourceMode) -> String {
        switch mode {
        case .autoDesktopFirst:
            return localized(.sourceAuto)
        case .codexApp:
            return localized(.sourceApp)
        case .codexCLI:
            return localized(.sourceCLI)
        case .customPath:
            return localized(.sourceCustom)
        }
    }

    func languageModeTitle(_ mode: LanguageMode) -> String {
        switch mode {
        case .system:
            return localized(.languageSystem)
        case .en:
            return localized(.languageEnglish)
        case .ja:
            return localized(.languageJapanese)
        }
    }

    func label(for kind: BucketKind) -> String {
        switch kind {
        case .fiveHour:
            return "5h"
        case .sevenDay:
            return "7d"
        case .review:
            return "Review"
        case .gptSpark:
            return "GPT Spark"
        case .custom:
            return "Custom"
        }
    }

    func trendDelta(for kind: BucketKind) -> Double? {
        let points = historyPoints
            .filter { $0.kind == kind }
            .sorted { $0.dateLocal < $1.dateLocal }
        guard points.count >= 2 else {
            return nil
        }
        let latest = points[points.count - 1].remainingPercent
        let previous = points[points.count - 2].remainingPercent
        return latest - previous
    }

    func menuBarTitle() -> String {
        let visible = visibleSummariesForMenu
        guard !visible.isEmpty else {
            return "--"
        }

        let items = visible.prefix(max(1, settings.inlineMaxCount))
        let texts = items.map { summary -> String in
            let suffix = settings.privacyMode
                ? localized(.menuPrivacyMasked)
                : DateUtils.displayPercent(summary.primary.remainingPercent)
            return "\(summary.shortLabel) \(suffix)"
        }

        var title = texts.joined(separator: " | ")
        if visible.count > settings.inlineMaxCount {
            let hidden = visible.count - settings.inlineMaxCount
            title += " +\(hidden)"
        }
        return title
    }

    func setSourceMode(_ mode: SourceMode) {
        settings.sourceMode = mode
        persistSettingsAndApply()
    }

    func setLanguageMode(_ mode: LanguageMode) {
        settings.languageMode = mode
        persistSettingsAndApply()
    }

    func setCustomCodexPath(_ path: String) {
        settings.customCodexPath = path
        persistSettingsAndApply()
    }

    func setStartAtLogin(_ enabled: Bool) {
        settings.startAtLogin = enabled
        do {
            try startAtLoginManager.setEnabled(enabled)
        } catch {
            Task {
                await database.appendDiagnostic(level: "error", code: "start_at_login", message: error.localizedDescription)
                await reloadDiagnostics()
            }
        }
        persistSettingsAndApply(applySource: false)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        settings.notificationsEnabled = enabled
        persistSettingsAndApply(applySource: false)
    }

    func updateThresholds(_ values: [Int]) {
        settings.thresholdPercents = values
        persistSettingsAndApply(applySource: false)
    }

    func setPrivacyMode(_ enabled: Bool) {
        settings.privacyMode = enabled
        persistSettingsAndApply(applySource: false)
    }

    func setInlineMaxCount(_ count: Int) {
        settings.inlineMaxCount = min(max(count, 1), 5)
        persistSettingsAndApply(applySource: false)
    }

    func setVisibleKind(_ kind: BucketKind, isVisible: Bool) {
        var kinds = settings.visibleKinds
        if isVisible {
            if !kinds.contains(kind) {
                kinds.append(kind)
            }
        } else {
            kinds.removeAll { $0 == kind }
        }
        if kinds.isEmpty {
            kinds = [.sevenDay]
        }
        settings.visibleKinds = kinds
        persistSettingsAndApply(applySource: false)
    }

    func setHistoryRangeDays(_ days: Int) {
        historyRangeDays = days
        Task {
            await reloadHistory()
        }
    }

    func toggleHistoryKind(_ kind: BucketKind) {
        if historyKinds.contains(kind) {
            historyKinds.remove(kind)
        } else {
            historyKinds.insert(kind)
        }
        Task {
            await reloadHistory()
        }
    }

    func setHistoryKind(_ kind: BucketKind, enabled: Bool) {
        if enabled {
            historyKinds.insert(kind)
        } else {
            historyKinds.remove(kind)
        }
        Task {
            await reloadHistory()
        }
    }

    func addAliasRule() {
        settings.aliasRules.append(LimitAliasRule(
            pattern: "",
            field: .limitId,
            targetKind: .custom,
            enabled: true,
            priority: 100
        ))
        persistAliasRulesOnly()
    }

    func removeAliasRule(id: UUID) {
        settings.aliasRules.removeAll { $0.id == id }
        persistAliasRulesOnly()
        recomputeSummaries()
    }

    func updateAliasRule(_ rule: LimitAliasRule) {
        guard let index = settings.aliasRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        settings.aliasRules[index] = rule
        persistAliasRulesOnly()
        recomputeSummaries()
    }

    func refreshNow() {
        Task {
            await service.refreshNow()
        }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func requestNotificationPermission() {
        Task {
            await notifier.requestAuthorizationIfNeeded()
        }
    }

    func openSystemNotificationSettings() {
        notifier.openSystemNotificationSettings()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "codex-credit-history.csv"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let header = "date,kind,remaining_percent,used_percent,source,captured_at_local\n"
        let rows = historyPoints.map { point in
            let used = point.usedPercent.map { String(format: "%.2f", $0) } ?? ""
            let captured = DateUtils.dateTimeFormatter.string(from: point.capturedAt)
            return "\(point.dateLocal),\(point.kind.rawValue),\(String(format: "%.2f", point.remainingPercent)),\(used),\(point.source.rawValue),\(captured)"
        }
        let content = header + rows.joined(separator: "\n")

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Task {
                await database.appendDiagnostic(level: "error", code: "csv_export", message: error.localizedDescription)
                await reloadDiagnostics()
            }
        }
    }

    private func bootstrap() {
        streamTask = Task {
            for await event in service.stream {
                switch event {
                case let .state(state):
                    serviceState = state
                    recomputeSummaries(rawBuckets: state.buckets)
                    await maybePersistSnapshotIfDue()
                    await notifier.evaluate(
                        summaries: summaries,
                        thresholds: settings.thresholdPercents,
                        enabled: settings.notificationsEnabled,
                        languageMode: settings.languageMode
                    )
                    await reloadDiagnostics()
                case .disconnected:
                    break
                }
            }
        }

        snapshotTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await maybePersistSnapshotIfDue()
            }
        }

        Task {
            let loaded = await database.loadSettings()
            let storedRules = await database.loadAliasRules()

            settings = loaded
            if !storedRules.isEmpty {
                settings.aliasRules = storedRules
            }

            let startAtLogin = startAtLoginManager.isEnabled()
            if settings.startAtLogin != startAtLogin {
                settings.startAtLogin = startAtLogin
                await database.saveSettings(settings)
            }

            await reloadDiagnostics()
            await reloadHistory()
            await notifier.requestAuthorizationIfNeeded()
            await service.applySettings(settings)
            await service.start()
        }
    }

    private func recomputeSummaries(rawBuckets: [LimitBucket]? = nil) {
        let buckets = rawBuckets ?? serviceState.buckets
        summaries = classification.summarize(buckets: buckets, rules: settings.aliasRules)
    }

    private func persistSettingsAndApply(applySource: Bool = true) {
        let settingsCopy = settings
        Task {
            await database.saveSettings(settingsCopy)
            await database.saveAliasRules(settingsCopy.aliasRules)
            if applySource {
                await service.applySettings(settingsCopy)
            }
            await reloadHistory()
        }
    }

    private func persistAliasRulesOnly() {
        let settingsCopy = settings
        Task {
            await database.saveSettings(settingsCopy)
            await database.saveAliasRules(settingsCopy.aliasRules)
        }
    }

    private func maybePersistSnapshotIfDue() async {
        guard !summaries.isEmpty else {
            return
        }

        let todayKey = DateUtils.localDateKey()
        if settings.lastSnapshotDateKey == todayKey {
            return
        }

        guard DateUtils.nowPastSnapshotTime(hour: 2) else {
            return
        }

        let source: SnapshotSource = serviceState.lastUpdatedAt != nil ? .exact : .carriedForward
        let now = Date()

        let points = summaries.map { summary in
            SnapshotPoint(
                id: "\(todayKey)-\(summary.kind.rawValue)",
                dateLocal: todayKey,
                capturedAt: now,
                kind: summary.kind,
                limitId: summary.primary.limitId,
                remainingPercent: summary.primary.remainingPercent,
                usedPercent: summary.primary.usedPercent,
                source: source
            )
        }

        await database.saveSnapshotPoints(points)
        await database.pruneSnapshots(olderThanDays: settings.retentionDays)

        settings.lastSnapshotDateKey = todayKey
        await database.saveSettings(settings)
        await reloadHistory()
    }

    private func reloadHistory() async {
        let points = await database.fetchSnapshots(days: historyRangeDays, kinds: historyKinds)
        historyPoints = points
    }

    private func reloadDiagnostics() async {
        diagnostics = await database.fetchDiagnostics(limit: 200)
    }
}
