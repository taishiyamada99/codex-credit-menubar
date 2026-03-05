import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    enum ManualRefreshState: Equatable {
        case idle
        case refreshing(Date)
        case success(Date)
        case failed(Date, String?)
    }

    @Published var settings: AppSettings
    @Published var serviceState: ServiceState
    @Published var summaries: [BucketSummary]
    @Published var diagnostics: [DiagnosticEvent]
    @Published var historyPoints: [SnapshotPoint]
    @Published var historyRangeDays: Int
    @Published var historyKinds: Set<BucketKind>
    @Published var activeSettingsTab: SettingsTab
    @Published var manualRefreshState: ManualRefreshState

    private let classification = ClassificationEngine()
    private let database: AppDatabase
    private let service: CodexRateLimitService
    private let startAtLoginManager = StartAtLoginManager()

    private var streamTask: Task<Void, Never>?
    private var shortSamplingTask: Task<Void, Never>?
    private var longTermSamplingTask: Task<Void, Never>?
    private var manualRefreshTimeoutTask: Task<Void, Never>?
    private var pendingManualRefreshToken: UUID?

    init() {
        let db = AppDatabase()
        self.database = db
        self.settings = .default
        self.serviceState = .initial
        self.summaries = []
        self.diagnostics = []
        self.historyPoints = []
        self.historyRangeDays = 30
        self.historyKinds = Set(BucketKind.fallbackCases)
        self.activeSettingsTab = .general
        self.manualRefreshState = .idle

        self.service = CodexRateLimitService(settings: .default) { [db] level, code, message in
            Task {
                await db.appendDiagnostic(level: level, code: code, message: message)
            }
        }

        bootstrap()
    }

    deinit {
        streamTask?.cancel()
        shortSamplingTask?.cancel()
        longTermSamplingTask?.cancel()
        manualRefreshTimeoutTask?.cancel()
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

    var manualRefreshSummaryText: String? {
        switch manualRefreshState {
        case .idle:
            return nil
        case .refreshing:
            return "\(localized(.manualRefresh)): \(localized(.refreshing))"
        case let .success(at):
            return "\(localized(.manualRefresh)): \(localized(.refreshSuccess)) — \(DateUtils.dateTimeFormatter.string(from: at))"
        case let .failed(at, message):
            let base = "\(localized(.manualRefresh)): \(localized(.refreshFailed)) — \(DateUtils.dateTimeFormatter.string(from: at))"
            guard let message, !message.isEmpty else {
                return base
            }
            return "\(base) (\(message))"
        }
    }

    var manualRefreshSummaryColor: Color {
        switch manualRefreshState {
        case .idle:
            return .secondary
        case .refreshing:
            return .secondary
        case .success:
            return .green
        case .failed:
            return .red
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

    func longTermRetentionTitle(_ retention: LongTermRetention) -> String {
        switch retention {
        case .oneYear:
            return localized(.retentionOneYear)
        case .twoYears:
            return localized(.retentionTwoYears)
        case .fiveYears:
            return localized(.retentionFiveYears)
        case .unlimited:
            return localized(.retentionUnlimited)
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
            .sorted { $0.capturedAt < $1.capturedAt }
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
            effectiveStatus: effectiveStatus
        )
    }

    nonisolated static func buildMenuBarTitle(
        summaries: [BucketSummary],
        settings: AppSettings,
        serviceState: ServiceState,
        effectiveStatus: AppHealthStatus
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
        let visibleCount = 3
        let items = kinds.prefix(visibleCount)

        let texts = items.compactMap { kind -> String? in
            guard let summary = byKind[kind] else {
                return nil
            }
            let suffix = DateUtils.displayPercent(summary.primary.remainingPercent)
            return "\(summary.shortLabel)\(suffix)"
        }

        if texts.isEmpty {
            return "--"
        }

        var title = texts.joined(separator: " ")
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

    func setLongTermRetention(_ retention: LongTermRetention) {
        settings.longTermRetention = retention
        persistSettingsAndApply(applySource: false)
        Task {
            await database.pruneLongTermRawDaily(retention: retention)
            await reloadHistory()
        }
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

    func refreshNow() {
        let token = UUID()
        pendingManualRefreshToken = token
        manualRefreshState = .refreshing(Date())
        manualRefreshTimeoutTask?.cancel()
        manualRefreshTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                guard self.pendingManualRefreshToken == token else {
                    return
                }
                self.pendingManualRefreshToken = nil
                self.manualRefreshState = .failed(Date(), nil)
            }
        }

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

    func refreshDiagnosticsNow() {
        Task {
            await reloadDiagnostics()
        }
    }

    func copyDiagnosticsToClipboard() {
        let lines = diagnostics.map { item in
            let timestamp = DateUtils.dateTimeFormatter.string(from: item.createdAt)
            return "[\(item.level.uppercased())] \(item.code) \(timestamp)\n\(item.message)"
        }
        let content = lines.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
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
                    applyManualRefreshResultIfNeeded(from: state)
                    recomputeSummaries(rawBuckets: state.buckets)
                    syncKindsToAvailable()
                    await maybePersistShortRawIfDue()
                    await maybePersistLongTermRawIfDue()
                case .disconnected:
                    break
                }
            }
        }

        shortSamplingTask = Task {
            while !Task.isCancelled {
                await maybePersistShortRawIfDue()
                let nextBoundary = DateUtils.nextFiveMinuteBoundary()
                let delay = max(5, nextBoundary.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        longTermSamplingTask = Task {
            while !Task.isCancelled {
                await maybePersistLongTermRawIfDue()
                let nextMidnight = DateUtils.nextGMTMidnight()
                let delay = max(30, nextMidnight.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        Task {
            let loaded = await database.loadSettings()
            let originalSettings = loaded

            settings = loaded
            settings.visibleKinds = normalizedVisibleKinds(settings.visibleKinds, allowedKinds: BucketKind.fallbackCases)
            historyKinds = Set(BucketKind.fallbackCases)

            let startAtLogin = startAtLoginManager.isEnabled()
            if settings.startAtLogin != startAtLogin {
                settings.startAtLogin = startAtLogin
            }

            if settings != originalSettings {
                await database.saveSettings(settings)
            }

            await reloadDiagnostics()
            await reloadHistory()
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

    private func applyManualRefreshResultIfNeeded(from state: ServiceState) {
        guard pendingManualRefreshToken != nil else {
            return
        }
        switch state.status {
        case .ok:
            manualRefreshTimeoutTask?.cancel()
            pendingManualRefreshToken = nil
            manualRefreshState = .success(state.lastUpdatedAt ?? Date())
        case .error:
            manualRefreshTimeoutTask?.cancel()
            pendingManualRefreshToken = nil
            manualRefreshState = .failed(Date(), state.message)
        case .loading, .stale:
            break
        }
    }

    private func syncKindsToAvailable() {
        let allowedKinds = selectableKinds
        let normalizedVisible = normalizedVisibleKinds(settings.visibleKinds, allowedKinds: allowedKinds)
        let normalizedHistory = Set(historyKinds.filter { allowedKinds.contains($0) })

        var changed = false
        var historyChanged = false
        if normalizedVisible != settings.visibleKinds {
            settings.visibleKinds = normalizedVisible
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

    private func recomputeSummaries(rawBuckets: [LimitBucket]? = nil) {
        let buckets = rawBuckets ?? serviceState.buckets
        summaries = classification.summarize(buckets: buckets)
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

    private func buildRawSamples(source: SnapshotSource) -> [RawBucketSample] {
        return serviceState.buckets.map { bucket in
            let kind = classification.classify(bucket: bucket)
            return RawBucketSample(
                // Preserve both primary/secondary windows even when they share the same limitId.
                limitId: Self.storageLimitIdentifier(for: bucket),
                limitName: bucket.limitName,
                kind: kind,
                remainingPercent: bucket.remainingPercent,
                usedPercent: bucket.usedPercent,
                resetsAt: bucket.resetsAt,
                source: source
            )
        }
    }

    nonisolated static func storageLimitIdentifier(for bucket: LimitBucket) -> String {
        let windowPart = bucket.windowDurationMins.map(String.init) ?? "na"
        let resetPart = bucket.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "na"
        return "\(bucket.limitId)#w\(windowPart)#r\(resetPart)"
    }

    private func maybePersistShortRawIfDue() async {
        guard !serviceState.buckets.isEmpty else {
            return
        }
        let slotEpoch = DateUtils.fiveMinuteSlotEpoch()
        let source: SnapshotSource = serviceState.lastUpdatedAt != nil ? .exact : .carriedForward
        let samples = buildRawSamples(source: source)
        guard !samples.isEmpty else {
            return
        }
        if settings.lastShortSlotEpoch == slotEpoch {
            let existingCount = await database.countShortRawSamples(slotEpoch: slotEpoch)
            if existingCount >= samples.count {
                return
            }
        }
        await database.saveShortRawSamples(
            slotEpoch: slotEpoch,
            capturedAt: Date(timeIntervalSince1970: TimeInterval(slotEpoch)),
            samples: samples
        )
        let shortRetentionSeconds: Int64 = 28 * 24 * 60 * 60
        await database.pruneShortRawSamples(olderThanSlotEpoch: slotEpoch - shortRetentionSeconds)
        settings.lastShortSlotEpoch = slotEpoch
        await database.saveSettings(settings)
        if historyRangeDays <= 30 {
            await reloadHistory()
        }
    }

    private func maybePersistLongTermRawIfDue() async {
        guard !serviceState.buckets.isEmpty else {
            return
        }
        let dayKeyGMT = DateUtils.gmtDateKey()
        let source: SnapshotSource = serviceState.lastUpdatedAt != nil ? .exact : .carriedForward
        let samples = buildRawSamples(source: source)
        guard !samples.isEmpty else {
            return
        }
        if settings.lastLongTermDayKeyGMT == dayKeyGMT {
            let existingCount = await database.countLongTermRawSamples(dayKeyGMT: dayKeyGMT)
            if existingCount >= samples.count {
                return
            }
        }
        await database.saveLongTermRawDaily(dayKeyGMT: dayKeyGMT, capturedAt: Date(), samples: samples)
        await database.pruneLongTermRawDaily(retention: settings.longTermRetention)
        settings.lastLongTermDayKeyGMT = dayKeyGMT
        await database.saveSettings(settings)
        if historyRangeDays >= 30 {
            await reloadHistory()
        }
    }

    private func reloadHistory() async {
        let now = Date()
        if historyRangeDays <= 30 {
            let cutoffDate = now.addingTimeInterval(-Double(historyRangeDays * 24 * 60 * 60))
            let cutoffSlot = DateUtils.fiveMinuteSlotEpoch(from: cutoffDate)
            var points = await database.fetchShortRawHistory(fromSlotEpoch: cutoffSlot, kinds: historyKinds)

            if historyRangeDays > 28 {
                let longCutoffDate = now.addingTimeInterval(-Double(historyRangeDays * 24 * 60 * 60))
                let longCutoffDay = DateUtils.gmtDateKey(from: longCutoffDate)
                let shortWindowStart = now.addingTimeInterval(-Double(28 * 24 * 60 * 60))
                let longPoints = await database.fetchLongTermRawHistory(fromDayKeyGMT: longCutoffDay, kinds: historyKinds)
                points.append(contentsOf: longPoints.filter { $0.capturedAt < shortWindowStart })
            }

            historyPoints = points.sorted { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.capturedAt < rhs.capturedAt
            }
            return
        }

        let cutoffDate = now.addingTimeInterval(-Double(historyRangeDays * 24 * 60 * 60))
        let cutoffDay = DateUtils.gmtDateKey(from: cutoffDate)
        let points = await database.fetchLongTermRawHistory(fromDayKeyGMT: cutoffDay, kinds: historyKinds)
        historyPoints = points
    }

    private func reloadDiagnostics() async {
        diagnostics = await database.fetchDiagnostics(limit: 200)
    }
}
