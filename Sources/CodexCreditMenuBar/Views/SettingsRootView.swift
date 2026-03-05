import Charts
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView(selection: Binding(
            get: { viewModel.activeSettingsTab },
            set: { viewModel.setActiveSettingsTab($0) }
        )) {
            GeneralSettingsTab(viewModel: viewModel)
                .tag(SettingsTab.general)
                .tabItem {
                    Text(viewModel.localized(.general))
                }

            UsageSettingsTab(viewModel: viewModel)
                .tag(SettingsTab.usage)
                .tabItem {
                    Text(viewModel.localized(.usage))
                }

            DiagnosticsSettingsTab(viewModel: viewModel)
                .tag(SettingsTab.diagnostics)
                .tabItem {
                    Text(viewModel.localized(.diagnostics))
                }
        }
        .padding(10)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(title: viewModel.localized(.connection)) {
                    Picker(viewModel.localized(.source), selection: Binding(
                        get: { viewModel.settings.sourceMode },
                        set: { viewModel.setSourceMode($0) }
                    )) {
                        ForEach(SourceMode.allCases) { mode in
                            Text(viewModel.sourceModeTitle(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if viewModel.settings.sourceMode == .customPath {
                        TextField(
                            viewModel.localized(.customPath),
                            text: Binding(
                                get: { viewModel.settings.customCodexPath },
                                set: { viewModel.setCustomCodexPath($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text(viewModel.localized(.currentSource))
                        Spacer()
                        Text(viewModel.serviceState.sourceLabel)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(viewModel.localized(.status))
                        Spacer()
                        Text(viewModel.healthText)
                            .foregroundStyle(colorForHealth(viewModel.effectiveStatus))
                    }

                    if let updated = viewModel.serviceState.lastUpdatedAt {
                        HStack {
                            Text(viewModel.localized(.lastUpdated))
                            Spacer()
                            Text(DateUtils.dateTimeFormatter.string(from: updated))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message = viewModel.serviceState.message, !message.isEmpty {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Picker(viewModel.localized(.language), selection: Binding(
                        get: { viewModel.settings.languageMode },
                        set: { viewModel.setLanguageMode($0) }
                    )) {
                        ForEach(LanguageMode.allCases) { mode in
                            Text(viewModel.languageModeTitle(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                SettingsSectionCard(title: viewModel.localized(.visibleInMenu)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.localized(.visibleInMenu))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(viewModel.selectableKinds) { kind in
                            Toggle(viewModel.label(for: kind), isOn: Binding(
                                get: { viewModel.settings.visibleKinds.contains(kind) },
                                set: { viewModel.setVisibleKind(kind, isVisible: $0) }
                            ))
                        }
                    }
                }

                SettingsSectionCard(title: viewModel.localized(.usageDataRetention)) {
                    Text(viewModel.localized(.shortStoragePolicy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.localized(.longStoragePolicy))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(viewModel.localized(.longTermRetention), selection: Binding(
                        get: { viewModel.settings.longTermRetention },
                        set: { viewModel.setLongTermRetention($0) }
                    )) {
                        ForEach(LongTermRetention.allCases) { retention in
                            Text(viewModel.longTermRetentionTitle(retention)).tag(retention)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 10) {
                    Button(viewModel.localized(.refreshNow)) {
                        viewModel.refreshNow()
                    }
                    .buttonStyle(.borderedProminent)

                    Toggle(viewModel.localized(.startAtLogin), isOn: Binding(
                        get: { viewModel.settings.startAtLogin },
                        set: { viewModel.setStartAtLogin($0) }
                    ))
                }

                if let refreshSummary = viewModel.manualRefreshSummaryText {
                    Text(refreshSummary)
                        .font(.caption)
                        .foregroundStyle(viewModel.manualRefreshSummaryColor)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func colorForHealth(_ status: AppHealthStatus) -> Color {
        switch status {
        case .ok:
            return .primary
        case .loading:
            return .secondary
        case .stale:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct UsageSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    private struct ChartPoint: Identifiable {
        let id: String
        let date: Date
        let kind: BucketKind
        let remaining: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(title: viewModel.localized(.usageOverview)) {
                    HStack(spacing: 12) {
                        UsageMetricCard(
                            title: "7D Remaining",
                            value: valueText(for: .sevenDay),
                            meta: metaText(for: .sevenDay),
                            tint: .blue,
                            background: Color.blue.opacity(0.10)
                        )

                        UsageMetricCard(
                            title: "5H Remaining",
                            value: valueText(for: .fiveHour),
                            meta: metaText(for: .fiveHour),
                            tint: .green,
                            background: Color.green.opacity(0.10)
                        )

                        UsageMetricCard(
                            title: "Spark Remaining",
                            value: valueText(for: .gptSpark),
                            meta: metaText(for: .gptSpark),
                            tint: .orange,
                            background: Color.orange.opacity(0.10)
                        )
                    }

                    Picker("", selection: Binding(
                        get: { viewModel.historyRangeDays },
                        set: { viewModel.setHistoryRangeDays($0) }
                    )) {
                        Text("7D").tag(7)
                        Text("30D").tag(30)
                        Text("90D").tag(90)
                        Text("180D").tag(180)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        ForEach(viewModel.selectableKinds) { kind in
                            Button {
                                viewModel.toggleHistoryKind(kind)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(color(for: kind))
                                        .frame(width: 8, height: 8)
                                    Text(viewModel.label(for: kind))
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    viewModel.historyKinds.contains(kind)
                                        ? color(for: kind).opacity(0.18)
                                        : Color.secondary.opacity(0.10)
                                )
                                .foregroundStyle(
                                    viewModel.historyKinds.contains(kind)
                                        ? color(for: kind)
                                        : Color.secondary
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if chartData.isEmpty {
                        Text(viewModel.localized(.noData))
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(chartData) { item in
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Remaining", item.remaining)
                            )
                            .foregroundStyle(color(for: item.kind))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)

                            PointMark(
                                x: .value("Date", item.date),
                                y: .value("Remaining", item.remaining)
                            )
                            .foregroundStyle(color(for: item.kind))
                            .symbolSize(20)
                        }
                        .chartYScale(domain: 0 ... 100)
                        .chartLegend(.hidden)
                        .frame(height: 280)
                    }

                    HStack(spacing: 8) {
                        StatusChip(
                            text: "\(viewModel.localized(.autoRefresh)): \(viewModel.settings.refreshIntervalMinutes) min",
                            tint: .indigo
                        )
                        StatusChip(text: viewModel.localized(.localSnapshots), tint: .mint)
                        Spacer()
                        Button(viewModel.localized(.exportCSV)) {
                            viewModel.exportCSV()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var summaryByKind: [BucketKind: BucketSummary] {
        Dictionary(uniqueKeysWithValues: viewModel.summaries.map { ($0.kind, $0) })
    }

    private var chartData: [ChartPoint] {
        let allowed = viewModel.historyKinds
        return viewModel.historyPoints
            .filter { allowed.contains($0.kind) }
            .map { point in
                ChartPoint(
                    id: point.id,
                    date: point.capturedAt,
                    kind: point.kind,
                    remaining: point.remainingPercent
                )
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.date < rhs.date
            }
    }

    private func valueText(for kind: BucketKind) -> String {
        guard let summary = summaryByKind[kind] else {
            return "--"
        }
        return DateUtils.displayPercent(summary.primary.remainingPercent)
    }

    private func metaText(for kind: BucketKind) -> String {
        guard let summary = summaryByKind[kind] else {
            return viewModel.localized(.noData)
        }
        if let reset = summary.primary.resetsAt {
            return "\(viewModel.localized(.resetAt)): \(DateUtils.dateTimeFormatter.string(from: reset))"
        }
        if kind == .gptSpark {
            return viewModel.localized(.rollingWindow)
        }
        return viewModel.localized(.noData)
    }

    private func color(for kind: BucketKind) -> Color {
        switch kind {
        case .sevenDay:
            return .blue
        case .fiveHour:
            return .green
        case .gptSpark:
            return .orange
        case .review:
            return .purple
        case .custom:
            return .secondary
        }
    }
}

private struct DiagnosticsSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(title: viewModel.localized(.appServerConnection)) {
                    Text("\(viewModel.localized(.source)): \(viewModel.sourceModeTitle(viewModel.settings.sourceMode))")
                    Text("\(viewModel.localized(.currentSource)): \(viewModel.serviceState.sourceLabel)")

                    HStack {
                        Text(viewModel.localized(.status))
                        Spacer()
                        Text(viewModel.healthText)
                            .foregroundStyle(colorForHealth(viewModel.effectiveStatus))
                    }

                    if let updated = viewModel.serviceState.lastUpdatedAt {
                        Text("\(viewModel.localized(.lastUpdated)): \(DateUtils.dateTimeFormatter.string(from: updated))")
                            .foregroundStyle(.secondary)
                    }

                    Text(viewModel.localized(.staleThresholdRule))
                        .foregroundStyle(.secondary)
                    Text(viewModel.localized(.reconnectBackoffRule))
                        .foregroundStyle(.secondary)

                    Text(viewModel.localized(.handledErrors))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(viewModel.localized(.handledErrorsLine1))
                        .foregroundStyle(.secondary)
                    Text(viewModel.localized(.handledErrorsLine2))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button(viewModel.localized(.refreshNow)) {
                            viewModel.refreshNow()
                            viewModel.refreshDiagnosticsNow()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(viewModel.localized(.copyLogs)) {
                            viewModel.copyDiagnosticsToClipboard()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsSectionCard(title: viewModel.localized(.recentEvents)) {
                    if viewModel.diagnostics.isEmpty {
                        Text(viewModel.localized(.diagnosticsEmpty))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.diagnostics) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("[\(item.level.uppercased())] \(item.code)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.message)
                                        .font(.body)
                                    Text(DateUtils.dateTimeFormatter.string(from: item.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                Text(viewModel.localized(.troubleshootingOnly))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            viewModel.refreshDiagnosticsNow()
        }
    }

    private func colorForHealth(_ status: AppHealthStatus) -> Color {
        switch status {
        case .ok:
            return .primary
        case .loading:
            return .secondary
        case .stale:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let meta: String
    let tint: Color
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .default))
                .foregroundStyle(tint)
            Text(meta)
                .font(.caption)
                .foregroundStyle(tint.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }
}
