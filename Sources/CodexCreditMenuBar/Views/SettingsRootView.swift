import Charts
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.general))
                }

            DisplaySettingsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.display))
                }

            HistorySettingsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.history))
                }

            NotificationSettingsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.notifications))
                }

            LanguageSettingsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.language))
                }

            DiagnosticsTab(viewModel: viewModel)
                .tabItem {
                    Text(viewModel.localized(.diagnostics))
                }
        }
        .padding(16)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker(viewModel.localized(.source), selection: Binding(
                get: { viewModel.settings.sourceMode },
                set: { viewModel.setSourceMode($0) }
            )) {
                ForEach(SourceMode.allCases) { mode in
                    Text(viewModel.sourceModeTitle(mode)).tag(mode)
                }
            }

            if viewModel.settings.sourceMode == .customPath {
                TextField(
                    viewModel.localized(.customPath),
                    text: Binding(
                        get: { viewModel.settings.customCodexPath },
                        set: { viewModel.setCustomCodexPath($0) }
                    )
                )
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
            }

            HStack {
                Button(viewModel.localized(.refreshNow)) {
                    viewModel.refreshNow()
                }
                Spacer()
                Toggle(viewModel.localized(.startAtLogin), isOn: Binding(
                    get: { viewModel.settings.startAtLogin },
                    set: { viewModel.setStartAtLogin($0) }
                ))
            }
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

private struct DisplaySettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.localized(.visibleInMenu))
                .font(.headline)

            ForEach(BucketKind.allCases) { kind in
                Toggle(viewModel.label(for: kind), isOn: Binding(
                    get: { viewModel.settings.visibleKinds.contains(kind) },
                    set: { viewModel.setVisibleKind(kind, isVisible: $0) }
                ))
            }

            Stepper(
                "\(viewModel.localized(.maxInline)): \(viewModel.settings.inlineMaxCount)",
                value: Binding(
                    get: { viewModel.settings.inlineMaxCount },
                    set: { viewModel.setInlineMaxCount($0) }
                ),
                in: 1 ... 5
            )

            Toggle(viewModel.localized(.privacyMode), isOn: Binding(
                get: { viewModel.settings.privacyMode },
                set: { viewModel.setPrivacyMode($0) }
            ))

            Divider()

            HStack {
                Text(viewModel.localized(.aliasRules))
                    .font(.headline)
                Spacer()
                Button(viewModel.localized(.addRule)) {
                    viewModel.addAliasRule()
                }
            }

            if viewModel.settings.aliasRules.isEmpty {
                Text(viewModel.localized(.noData))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(viewModel.settings.aliasRules.indices, id: \.self) { index in
                        AliasRuleRow(
                            rule: Binding(
                                get: { viewModel.settings.aliasRules[index] },
                                set: { viewModel.updateAliasRule($0) }
                            ),
                            viewModel: viewModel,
                            onRemove: { viewModel.removeAliasRule(id: $0.id) }
                        )
                    }
                }
            }
        }
    }
}

private struct AliasRuleRow: View {
    @Binding var rule: LimitAliasRule
    @ObservedObject var viewModel: AppViewModel
    let onRemove: (LimitAliasRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()

            TextField(viewModel.localized(.rulePattern), text: $rule.pattern)

            Picker(viewModel.localized(.ruleField), selection: $rule.field) {
                ForEach(AliasField.allCases) { field in
                    Text(field.rawValue).tag(field)
                }
            }

            Picker(viewModel.localized(.ruleTarget), selection: $rule.targetKind) {
                ForEach(BucketKind.allCases) { kind in
                    Text(viewModel.label(for: kind)).tag(kind)
                }
            }

            Stepper(
                "\(viewModel.localized(.rulePriority)): \(rule.priority)",
                value: $rule.priority,
                in: 0 ... 500
            )

            HStack {
                Button(viewModel.localized(.remove)) {
                    onRemove(rule)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .cornerRadius(8)
    }
}

private struct HistorySettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    private struct ChartPoint: Identifiable {
        let id: String
        let date: Date
        let kind: BucketKind
        let remaining: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(viewModel.localized(.snapshotsRange), selection: Binding(
                get: { viewModel.historyRangeDays },
                set: { viewModel.setHistoryRangeDays($0) }
            )) {
                Text(viewModel.localized(.days7)).tag(7)
                Text(viewModel.localized(.days30)).tag(30)
                Text(viewModel.localized(.days90)).tag(90)
                Text(viewModel.localized(.days180)).tag(180)
            }
            .pickerStyle(.segmented)

            HStack {
                ForEach(BucketKind.allCases) { kind in
                    Toggle(viewModel.label(for: kind), isOn: Binding(
                        get: { viewModel.historyKinds.contains(kind) },
                        set: { viewModel.setHistoryKind(kind, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
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
                    .foregroundStyle(by: .value("Kind", viewModel.label(for: item.kind)))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Remaining", item.remaining)
                    )
                    .foregroundStyle(by: .value("Kind", viewModel.label(for: item.kind)))
                }
                .frame(height: 280)
            }

            Button(viewModel.localized(.exportCSV)) {
                viewModel.exportCSV()
            }
        }
    }

    private var chartData: [ChartPoint] {
        viewModel.historyPoints.compactMap { point in
            guard let date = DateUtils.dateFromLocalDateKey(point.dateLocal) else {
                return nil
            }
            return ChartPoint(
                id: point.id,
                date: date,
                kind: point.kind,
                remaining: point.remainingPercent
            )
        }
    }
}

private struct NotificationSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Toggle(viewModel.localized(.enabled), isOn: Binding(
                get: { viewModel.settings.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
            ))

            let thresholds = sortedThresholds
            ForEach(thresholds.indices, id: \.self) { index in
                let current = thresholds[index]
                Stepper(
                    "\(viewModel.localized(.thresholds)) \(index + 1): \(current)%",
                    value: Binding(
                        get: { sortedThresholds[index] },
                        set: { newValue in
                            var values = sortedThresholds
                            values[index] = max(1, min(100, newValue))
                            viewModel.updateThresholds(values)
                        }
                    ),
                    in: 1 ... 100
                )
            }

            HStack {
                Button(viewModel.localized(.requestNotification)) {
                    viewModel.requestNotificationPermission()
                }

                Button(viewModel.localized(.openNotificationSettings)) {
                    viewModel.openSystemNotificationSettings()
                }
            }
        }
    }

    private var sortedThresholds: [Int] {
        viewModel.settings.thresholdPercents.sorted()
    }
}

private struct LanguageSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker(viewModel.localized(.language), selection: Binding(
                get: { viewModel.settings.languageMode },
                set: { viewModel.setLanguageMode($0) }
            )) {
                ForEach(LanguageMode.allCases) { mode in
                    Text(viewModel.languageModeTitle(mode)).tag(mode)
                }
            }
        }
    }
}

private struct DiagnosticsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.localized(.appServerConnection))
                    .font(.headline)
                Spacer()
                Button(viewModel.localized(.refreshNow)) {
                    viewModel.refreshNow()
                }
            }

            if viewModel.diagnostics.isEmpty {
                Text(viewModel.localized(.diagnosticsEmpty))
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.diagnostics) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(item.level.uppercased())] \(item.code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.message)
                            .font(.body)
                        Text(DateUtils.dateTimeFormatter.string(from: item.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
