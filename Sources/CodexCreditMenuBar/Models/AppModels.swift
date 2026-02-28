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

enum SnapshotSource: String, Codable {
    case exact
    case carriedForward
}

enum AliasField: String, Codable, CaseIterable, Identifiable {
    case limitId
    case limitName

    var id: String { rawValue }
}

struct LimitAliasRule: Codable, Identifiable, Hashable {
    var id: UUID
    var pattern: String
    var field: AliasField
    var targetKind: BucketKind
    var enabled: Bool
    var priority: Int

    init(
        id: UUID = UUID(),
        pattern: String,
        field: AliasField,
        targetKind: BucketKind,
        enabled: Bool = true,
        priority: Int = 100
    ) {
        self.id = id
        self.pattern = pattern
        self.field = field
        self.targetKind = targetKind
        self.enabled = enabled
        self.priority = priority
    }
}

struct AppSettings: Codable {
    var sourceMode: SourceMode
    var customCodexPath: String
    var visibleKinds: [BucketKind]
    var inlineMaxCount: Int
    var privacyMode: Bool
    var notificationsEnabled: Bool
    var thresholdPercents: [Int]
    var languageMode: LanguageMode
    var startAtLogin: Bool
    var lastSnapshotDateKey: String?
    var refreshIntervalMinutes: Int
    var retentionDays: Int
    var aliasRules: [LimitAliasRule]

    static let settingsKey = "app_settings"

    static let `default` = AppSettings(
        sourceMode: .autoDesktopFirst,
        customCodexPath: "",
        visibleKinds: [.sevenDay],
        inlineMaxCount: 2,
        privacyMode: false,
        notificationsEnabled: true,
        thresholdPercents: [20, 10, 5],
        languageMode: .en,
        startAtLogin: false,
        lastSnapshotDateKey: nil,
        refreshIntervalMinutes: 5,
        retentionDays: 180,
        aliasRules: []
    )
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
