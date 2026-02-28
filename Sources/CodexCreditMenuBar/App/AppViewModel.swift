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
    @Published var activeSettingsTab: SettingsTab

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
        self.historyKinds = Set(BucketKind.fallbackCases)
        self.activeSettingsTab = .general

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
        let kinds = normalizedVisibleKinds(settings.visibleKinds, allowedKinds: selectableKinds)
        let byKind = Dictionary(uniqueKeysWithValues: summaries.map { ($0.kind, $0) })
        return kinds.compactMap { byKind[$0] }
    }

    var selectableKinds: [BucketKind] {
        let availableSet = Set(summaries.map(\.kind))
        let available = BucketKind.uiCases.filter { availableSet.contains($0) }
        if !available.isEmpty {
            return available
        }
        return BucketKind.fallbackCases
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
        Self.buildMenuBarTitle(
            summaries: summaries,
            settings: settings,
            serviceState: serviceState,
            effectiveStatus: effectiveStatus,
            privacyMask: localized(.menuPrivacyMasked)
        )
    }

    nonisolated static func buildMenuBarTitle(
        summaries: [BucketSummary],
        settings: AppSettings,
        serviceState: ServiceState,
        effectiveStatus: AppHealthStatus,
        privacyMask: String
    ) -> String {
        if summaries.isEmpty {
            if serviceState.authRequired {
                return "AUTH"
            }
            switch effectiveStatus {
            case .loading:
                return "..."
            case .error:
                return "ERR"
            case .stale:
                return "STALE"
            case .ok:
                return "--"
            }
        }

        let byKind = Dictionary(uniqueKeysWithValues: summaries.map { ($0.kind, $0) })
        let orderedAvailable = BucketKind.uiCases.filter { byKind[$0] != nil }
        if orderedAvailable.isEmpty {
            return "--"
        }
        let fallbackAvailable = orderedAvailable
        var selectedSeen = Set<BucketKind>()
        let filteredKinds = settings.visibleKinds
            .filter { fallbackAvailable.contains($0) && selectedSeen.insert($0).inserted }
        let kinds = filteredKinds.isEmpty ? [fallbackAvailable[0]] : filteredKinds
        let visibleCount = max(1, min(settings.inlineMaxCount, 5))
        let items = kinds.prefix(visibleCount)

        let texts = items.compactMap { kind -> String? in
            guard let summary = byKind[kind] else {
                return nil
            }
            let suffix = settings.privacyMode
                ? privacyMask
                : DateUtils.displayPercent(summary.primary.remainingPercent)
            return "\(summary.shortLabel) \(suffix)"
        }

        if texts.isEmpty {
            return "--"
        }

        var title = texts.joined(separator: " | ")
        if kinds.count > visibleCount {
            let hidden = kinds.count - visibleCount
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
        let clamped = min(max(count, 1), 5)
        let requiredForSelection = min(5, normalizedVisibleKinds(settings.visibleKinds, allowedKinds: selectableKinds).count)
        settings.inlineMaxCount = max(clamped, requiredForSelection)
        persistSettingsAndApply(applySource: false)
    }

    func setVisibleKind(_ kind: BucketKind, isVisible: Bool) {
        guard selectableKinds.contains(kind) else {
            return
        }
        var kinds = settings.visibleKinds
        if isVisible {
            kinds.removeAll { $0 == kind }
            kinds.insert(kind, at: 0)
        } else {
            kinds.removeAll { $0 == kind }
        }
        let normalizedKinds = normalizedVisibleKinds(kinds, allowedKinds: selectableKinds)
        settings.visibleKinds = normalizedKinds
        settings.inlineMaxCount = max(settings.inlineMaxCount, min(5, normalizedKinds.count))
        persistSettingsAndApply(applySource: false)
    }

    func setHistoryRangeDays(_ days: Int) {
        historyRangeDays = days
        Task {
            await reloadHistory()
        }
    }

    func toggleHistoryKind(_ kind: BucketKind) {
        guard selectableKinds.contains(kind) else {
            return
        }
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
        guard selectableKinds.contains(kind) else {
            return
        }
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
            targetKind: .sevenDay,
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
        settings.aliasRules[index] = normalizedAliasRule(rule)
        persistAliasRulesOnly()
        recomputeSummaries()
    }

    func refreshNow() {
        Task {
            await service.refreshNow()
        }
    }

    func openSettings() {
        SettingsWindowManager.shared.show(viewModel: self)
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

    func refreshDiagnosticsNow() {
        Task {
            await reloadDiagnostics()
        }
    }

    func setActiveSettingsTab(_ tab: SettingsTab) {
        activeSettingsTab = tab
        SettingsWindowManager.shared.updateSize(for: tab)
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
                    syncKindsToAvailable()
                    await maybePersistSnapshotIfDue()
                    await notifier.evaluate(
                        summaries: summaries.filter { selectableKinds.contains($0.kind) },
                        thresholds: settings.thresholdPercents,
                        enabled: settings.notificationsEnabled,
                        languageMode: settings.languageMode
                    )
                case .disconnected:
                    break
                }
            }
        }

        snapshotTask = Task {
            while !Task.isCancelled {
                await maybePersistSnapshotIfDue()
                let delaySeconds = nextSnapshotCheckDelaySeconds()
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
        }

        Task {
            let loaded = await database.loadSettings()
            let storedRules = await database.loadAliasRules()
            let originalSettings = loaded
            var shouldPersistAliasRules = false

            settings = loaded
            settings.visibleKinds = normalizedVisibleKinds(settings.visibleKinds, allowedKinds: BucketKind.fallbackCases)
            let normalizedInline = min(max(settings.inlineMaxCount, 1), 5)
            settings.inlineMaxCount = max(normalizedInline, min(5, settings.visibleKinds.count))
            if !storedRules.isEmpty {
                settings.aliasRules = storedRules
            }
            let normalizedRules = normalizedAliasRules(settings.aliasRules)
            if normalizedRules != settings.aliasRules {
                settings.aliasRules = normalizedRules
                shouldPersistAliasRules = true
            }
            historyKinds = Set(BucketKind.fallbackCases)

            let startAtLogin = startAtLoginManager.isEnabled()
            if settings.startAtLogin != startAtLogin {
                settings.startAtLogin = startAtLogin
            }

            if settings != originalSettings {
                await database.saveSettings(settings)
            }
            if shouldPersistAliasRules {
                await database.saveAliasRules(settings.aliasRules)
            }

            await reloadDiagnostics()
            await reloadHistory()
            await notifier.requestAuthorizationIfNeeded()
            await service.applySettings(settings)
            await service.start()
        }
    }

    private func normalizedVisibleKinds(_ kinds: [BucketKind], allowedKinds: [BucketKind]) -> [BucketKind] {
        let allowed = Set(allowedKinds)
        var seen = Set<BucketKind>()
        let unique = kinds.filter { allowed.contains($0) && seen.insert($0).inserted }
        return unique.isEmpty ? [allowedKinds.first ?? .sevenDay] : unique
    }

    private func syncKindsToAvailable() {
        let allowedKinds = selectableKinds
        let normalizedVisible = normalizedVisibleKinds(settings.visibleKinds, allowedKinds: allowedKinds)
        let normalizedHistory = Set(historyKinds.filter { allowedKinds.contains($0) })

        var changed = false
        var historyChanged = false
        if normalizedVisible != settings.visibleKinds {
            settings.visibleKinds = normalizedVisible
            settings.inlineMaxCount = max(settings.inlineMaxCount, min(5, normalizedVisible.count))
            changed = true
        }

        if normalizedHistory != historyKinds {
            historyKinds = normalizedHistory.isEmpty ? Set(allowedKinds) : normalizedHistory
            historyChanged = true
        }

        if changed {
            persistSettingsAndApply(applySource: false)
        }
        if historyChanged {
            Task {
                await reloadHistory()
            }
        }
    }

    private func normalizedAliasRules(_ rules: [LimitAliasRule]) -> [LimitAliasRule] {
        rules.map { normalizedAliasRule($0) }
    }

    private func normalizedAliasRule(_ rule: LimitAliasRule) -> LimitAliasRule {
        guard rule.targetKind == .custom else {
            return rule
        }
        var updated = rule
        updated.targetKind = .sevenDay
        return updated
    }

    private func recomputeSummaries(rawBuckets: [LimitBucket]? = nil) {
        let buckets = rawBuckets ?? serviceState.buckets
        summaries = classification.summarize(buckets: buckets, rules: settings.aliasRules)
    }

    private func persistSettingsAndApply(applySource: Bool = true) {
        let settingsCopy = settings
        Task {
            await database.saveSettings(settingsCopy)
            if applySource {
                await service.applySettings(settingsCopy)
            }
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

        let points = summaries
            .filter { selectableKinds.contains($0.kind) }
            .map { summary in
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

        guard !points.isEmpty else {
            return
        }

        await database.saveSnapshotPoints(points)
        await database.pruneSnapshots(olderThanDays: settings.retentionDays)

        settings.lastSnapshotDateKey = todayKey
        await database.saveSettings(settings)
        await reloadHistory()
    }

    private func nextSnapshotCheckDelaySeconds() -> Int {
        let now = Date()
        if summaries.isEmpty {
            return 15 * 60
        }

        let todayKey = DateUtils.localDateKey(from: now)
        if settings.lastSnapshotDateKey == todayKey {
            let next = DateUtils.nextSnapshotDate(hour: 2)
            return max(5 * 60, Int(next.timeIntervalSince(now)))
        }

        if DateUtils.nowPastSnapshotTime(hour: 2) {
            return 5 * 60
        }

        let next = DateUtils.nextSnapshotDate(hour: 2)
        return max(60, Int(next.timeIntervalSince(now)))
    }

    private func reloadHistory() async {
        let points = await database.fetchSnapshots(days: historyRangeDays, kinds: historyKinds)
        historyPoints = points
    }

    private func reloadDiagnostics() async {
        diagnostics = await database.fetchDiagnostics(limit: 200)
    }
}
