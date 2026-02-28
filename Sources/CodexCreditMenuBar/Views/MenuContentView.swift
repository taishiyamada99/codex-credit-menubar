import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Section {
            if viewModel.summaries.isEmpty {
                Text(viewModel.localized(.noData))
            }

            ForEach(viewModel.summaries) { summary in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.title)
                        Spacer()
                        Text(viewModel.settings.privacyMode ? "••" : DateUtils.displayPercent(summary.primary.remainingPercent))
                        if let delta = viewModel.trendDelta(for: summary.kind) {
                            Text(trendSymbol(delta))
                                .foregroundStyle(deltaColor(delta))
                                .font(.caption)
                        }
                    }
                    .font(.body)

                    HStack(spacing: 8) {
                        if let reset = summary.primary.resetsAt {
                            Text("\(viewModel.localized(.resetAt)): \(DateUtils.timeFormatter.string(from: reset))")
                        }
                        if let updated = summary.primary.updatedAt ?? viewModel.serviceState.lastUpdatedAt {
                            Text("\(viewModel.localized(.lastUpdated)): \(DateUtils.timeFormatter.string(from: updated))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(viewModel.localized(.menuAllLimits))
        }

        Divider()

        Button(viewModel.localized(.refreshNow)) {
            viewModel.refreshNow()
        }

        Button(viewModel.localized(.openSettings)) {
            viewModel.openSettings()
        }

        Toggle(viewModel.localized(.startAtLogin), isOn: Binding(
            get: { viewModel.settings.startAtLogin },
            set: { viewModel.setStartAtLogin($0) }
        ))

        Menu(viewModel.localized(.language)) {
            ForEach(LanguageMode.allCases) { mode in
                Button(viewModel.languageModeTitle(mode)) {
                    viewModel.setLanguageMode(mode)
                }
            }
        }

        if viewModel.effectiveStatus == .stale {
            Divider()
            Text(viewModel.localized(.staleWarning))
                .foregroundStyle(.orange)
        }

        if let message = viewModel.serviceState.message, !message.isEmpty {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Divider()

        Button(viewModel.localized(.quit)) {
            viewModel.quitApp()
        }
    }

    private func trendSymbol(_ delta: Double) -> String {
        if delta > 0.5 {
            return "↑"
        }
        if delta < -0.5 {
            return "↓"
        }
        return "→"
    }

    private func deltaColor(_ delta: Double) -> Color {
        if delta > 0.5 {
            return .green
        }
        if delta < -0.5 {
            return .red
        }
        return .secondary
    }
}
