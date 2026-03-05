import Foundation

enum AppHealthStatus: String, Codable, CaseIterable {
    case loading
    case ok
    case stale
    case error
}

enum BucketKind: String, Codable, CaseIterable, Identifiable {
    case fiveHour
    case sevenDay
    case review
    case gptSpark
    case custom

    var id: String { rawValue }

    static let uiCases: [BucketKind] = [
        .sevenDay,
        .fiveHour,
        .review,
        .gptSpark
    ]

    static let fallbackCases: [BucketKind] = [
        .sevenDay,
        .fiveHour,
        .gptSpark
    ]

    var shortLabel: String {
        switch self {
        case .fiveHour:
            return "5H"
        case .sevenDay:
            return "7D"
        case .review:
            return "RV"
        case .gptSpark:
            return "SP"
        case .custom:
            return "C"
        }
    }
}

enum SourceMode: String, Codable, CaseIterable, Identifiable {
    case autoDesktopFirst
    case codexApp
    case codexCLI
    case customPath

    var id: String { rawValue }
}

enum LanguageMode: String, Codable, CaseIterable, Identifiable {
    case system
    case en
    case ja

    var id: String { rawValue }
}

enum LongTermRetention: String, Codable, CaseIterable, Identifiable {
    case oneYear
    case twoYears
    case fiveYears
    case unlimited

    var id: String { rawValue }

    var retentionDays: Int? {
        switch self {
        case .oneYear:
            return 365
        case .twoYears:
            return 730
        case .fiveYears:
            return 1_825
        case .unlimited:
            return nil
        }
    }
}

enum SnapshotSource: String, Codable {
    case exact
    case carriedForward
}

struct AppSettings: Codable, Equatable {
    var sourceMode: SourceMode
    var customCodexPath: String
    var visibleKinds: [BucketKind]
    var languageMode: LanguageMode
    var startAtLogin: Bool
    var lastSnapshotDateKey: String?
    var lastShortSlotEpoch: Int64?
    var lastLongTermDayKeyGMT: String?
    var refreshIntervalMinutes: Int
    var longTermRetention: LongTermRetention

    static let settingsKey = "app_settings"

    static let `default` = AppSettings(
        sourceMode: .autoDesktopFirst,
        customCodexPath: "",
        visibleKinds: [.sevenDay],
        languageMode: .en,
        startAtLogin: false,
        lastSnapshotDateKey: nil,
        lastShortSlotEpoch: nil,
        lastLongTermDayKeyGMT: nil,
        refreshIntervalMinutes: 5,
        longTermRetention: .twoYears
    )

    enum CodingKeys: String, CodingKey {
        case sourceMode
        case customCodexPath
        case visibleKinds
        case languageMode
        case startAtLogin
        case lastSnapshotDateKey
        case lastShortSlotEpoch
        case lastLongTermDayKeyGMT
        case refreshIntervalMinutes
        case longTermRetention
    }

    init(
        sourceMode: SourceMode,
        customCodexPath: String,
        visibleKinds: [BucketKind],
        languageMode: LanguageMode,
        startAtLogin: Bool,
        lastSnapshotDateKey: String?,
        lastShortSlotEpoch: Int64?,
        lastLongTermDayKeyGMT: String?,
        refreshIntervalMinutes: Int,
        longTermRetention: LongTermRetention
    ) {
        self.sourceMode = sourceMode
        self.customCodexPath = customCodexPath
        self.visibleKinds = visibleKinds
        self.languageMode = languageMode
        self.startAtLogin = startAtLogin
        self.lastSnapshotDateKey = lastSnapshotDateKey
        self.lastShortSlotEpoch = lastShortSlotEpoch
        self.lastLongTermDayKeyGMT = lastLongTermDayKeyGMT
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.longTermRetention = longTermRetention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        sourceMode = try container.decodeIfPresent(SourceMode.self, forKey: .sourceMode) ?? defaults.sourceMode
        customCodexPath = try container.decodeIfPresent(String.self, forKey: .customCodexPath) ?? defaults.customCodexPath
        visibleKinds = try container.decodeIfPresent([BucketKind].self, forKey: .visibleKinds) ?? defaults.visibleKinds
        languageMode = try container.decodeIfPresent(LanguageMode.self, forKey: .languageMode) ?? defaults.languageMode
        startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? defaults.startAtLogin
        lastSnapshotDateKey = try container.decodeIfPresent(String.self, forKey: .lastSnapshotDateKey)
        lastShortSlotEpoch = try container.decodeIfPresent(Int64.self, forKey: .lastShortSlotEpoch)
        lastLongTermDayKeyGMT = try container.decodeIfPresent(String.self, forKey: .lastLongTermDayKeyGMT)
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? defaults.refreshIntervalMinutes
        longTermRetention = try container.decodeIfPresent(LongTermRetention.self, forKey: .longTermRetention) ?? defaults.longTermRetention
    }
}

struct RawBucketSample: Hashable {
    let limitId: String
    let limitName: String
    let kind: BucketKind
    let remainingPercent: Double
    let usedPercent: Double
    let resetsAt: Date?
    let source: SnapshotSource
}

struct LimitBucket: Identifiable, Hashable {
    var id: String { limitId }
    let limitId: String
    let limitName: String
    let usedPercent: Double
    let remainingPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?
    let updatedAt: Date?
    let hasSecondary: Bool
}

struct BucketSummary: Identifiable, Hashable {
    let id: String
    let kind: BucketKind
    let title: String
    let shortLabel: String
    let primary: LimitBucket
    let secondary: LimitBucket?
    let members: [LimitBucket]
}

struct SnapshotPoint: Identifiable, Hashable {
    let id: String
    let dateLocal: String
    let capturedAt: Date
    let kind: BucketKind
    let limitId: String
    let remainingPercent: Double
    let usedPercent: Double?
    let source: SnapshotSource
}

struct DiagnosticEvent: Identifiable, Hashable {
    let id: Int64
    let level: String
    let code: String
    let message: String
    let createdAt: Date
}

struct ServiceState: Hashable {
    var sourceLabel: String
    var status: AppHealthStatus
    var lastUpdatedAt: Date?
    var buckets: [LimitBucket]
    var message: String?
    var authRequired: Bool

    static let initial = ServiceState(
        sourceLabel: "-",
        status: .loading,
        lastUpdatedAt: nil,
        buckets: [],
        message: nil,
        authRequired: false
    )
}

enum ServiceEvent: Hashable {
    case state(ServiceState)
    case disconnected
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case usage
    case diagnostics

    var id: String { rawValue }
}
