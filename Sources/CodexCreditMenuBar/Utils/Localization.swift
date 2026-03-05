import Foundation

enum L10nKey: String {
    case appName
    case refreshNow
    case openSettings
    case quit
    case startAtLogin
    case language
    case source
    case status
    case lastUpdated
    case resetAt
    case general
    case usage
    case display
    case history
    case diagnostics
    case connection
    case usageOverview
    case usageDataRetention
    case recentEvents
    case copyLogs
    case autoRefresh
    case localSnapshots
    case rollingWindow
    case staleThresholdRule
    case reconnectBackoffRule
    case handledErrors
    case handledErrorsLine1
    case handledErrorsLine2
    case troubleshootingOnly
    case enabled
    case disabled
    case save
    case visibleInMenu
    case noData
    case retention
    case exportCSV
    case accountSignInRequired
    case currentSource
    case customPath
    case appServerConnection
    case healthOk
    case healthLoading
    case healthStale
    case healthError
    case manualRefresh
    case refreshing
    case refreshSuccess
    case refreshFailed
    case menuAllLimits
    case staleWarning
    case settings
    case languageSystem
    case languageEnglish
    case languageJapanese
    case sourceAuto
    case sourceApp
    case sourceCLI
    case sourceCustom
    case snapshotsRange
    case days7
    case days30
    case days90
    case days180
    case diagnosticsEmpty
    case codexNotFound
    case authRequired
    case comparePrevDay
    case shortStoragePolicy
    case longStoragePolicy
    case longTermRetention
    case retentionOneYear
    case retentionTwoYears
    case retentionFiveYears
    case retentionUnlimited
}

enum L10n {
    static func text(_ key: L10nKey, languageMode: LanguageMode) -> String {
        let lang = resolvedLanguage(mode: languageMode)
        switch lang {
        case .ja:
            return ja[key] ?? en[key] ?? key.rawValue
        case .en:
            return en[key] ?? key.rawValue
        case .system:
            return en[key] ?? key.rawValue
        }
    }

    private static func resolvedLanguage(mode: LanguageMode) -> LanguageMode {
        guard mode == .system else {
            return mode
        }
        if Locale.current.language.languageCode?.identifier == "ja" {
            return .ja
        }
        return .en
    }

    private static let en: [L10nKey: String] = [
        .appName: "Codex Credits",
        .refreshNow: "Refresh now",
        .openSettings: "Open Settings",
        .quit: "Quit",
        .startAtLogin: "Start at Login",
        .language: "Language",
        .source: "Source",
        .status: "Status",
        .lastUpdated: "Last Updated",
        .resetAt: "Reset",
        .general: "General",
        .usage: "Usage",
        .display: "Display",
        .history: "History",
        .diagnostics: "Diagnostics",
        .connection: "Connection",
        .usageOverview: "Usage Overview",
        .usageDataRetention: "Usage Data Retention",
        .recentEvents: "Recent Events",
        .copyLogs: "Copy logs",
        .autoRefresh: "Auto-refresh",
        .localSnapshots: "Data shown: local snapshots",
        .rollingWindow: "Rolling window",
        .staleThresholdRule: "Stale threshold: 15 minutes without update",
        .reconnectBackoffRule: "Reconnect backoff: 5s -> 15s -> 30s -> 60s -> 300s",
        .handledErrors: "Handled errors",
        .handledErrorsLine1: "CodexNotFound / AuthRequired / RateLimitUnavailable",
        .handledErrorsLine2: "ServerOverloaded (-32001) with automatic retry",
        .troubleshootingOnly: "Diagnostics view is for troubleshooting only",
        .enabled: "Enabled",
        .disabled: "Disabled",
        .save: "Save",
        .visibleInMenu: "Visible in menu bar",
        .noData: "No data",
        .retention: "Retention",
        .exportCSV: "Export CSV",
        .accountSignInRequired: "Sign in required",
        .currentSource: "Current source",
        .customPath: "Custom codex path",
        .appServerConnection: "App Server Connection",
        .healthOk: "OK",
        .healthLoading: "Loading",
        .healthStale: "Stale",
        .healthError: "Error",
        .manualRefresh: "Manual refresh",
        .refreshing: "Refreshing",
        .refreshSuccess: "Success",
        .refreshFailed: "Failed",
        .menuAllLimits: "All limits",
        .staleWarning: "Data is stale",
        .settings: "Settings",
        .languageSystem: "System",
        .languageEnglish: "English",
        .languageJapanese: "Japanese",
        .sourceAuto: "Auto (Desktop-first)",
        .sourceApp: "Codex App",
        .sourceCLI: "Codex CLI",
        .sourceCustom: "Custom Path",
        .snapshotsRange: "Range",
        .days7: "7 days",
        .days30: "30 days",
        .days90: "90 days",
        .days180: "180 days",
        .diagnosticsEmpty: "No diagnostics",
        .codexNotFound: "Codex command not found",
        .authRequired: "Authentication required",
        .comparePrevDay: "vs prev day",
        .shortStoragePolicy: "Short-term storage: Raw, every 5 minutes, fixed 28 days",
        .longStoragePolicy: "Long-term storage: Raw, daily at GMT 00:00",
        .longTermRetention: "Long-term retention",
        .retentionOneYear: "1 year",
        .retentionTwoYears: "2 years",
        .retentionFiveYears: "5 years",
        .retentionUnlimited: "Unlimited"
    ]

    private static let ja: [L10nKey: String] = [
        .appName: "Codex クレジット",
        .refreshNow: "今すぐ更新",
        .openSettings: "設定を開く",
        .quit: "終了",
        .startAtLogin: "ログイン時に起動",
        .language: "言語",
        .source: "ソース",
        .status: "状態",
        .lastUpdated: "最終更新",
        .resetAt: "リセット",
        .general: "一般",
        .usage: "使用状況",
        .display: "表示",
        .history: "履歴",
        .diagnostics: "診断",
        .connection: "接続",
        .usageOverview: "使用状況",
        .usageDataRetention: "利用データ保持",
        .recentEvents: "最近のイベント",
        .copyLogs: "ログをコピー",
        .autoRefresh: "自動更新",
        .localSnapshots: "表示データ: ローカルスナップショット",
        .rollingWindow: "ローリングウィンドウ",
        .staleThresholdRule: "Stale判定: 更新なし15分",
        .reconnectBackoffRule: "再接続バックオフ: 5秒→15秒→30秒→60秒→300秒",
        .handledErrors: "対応済みエラー",
        .handledErrorsLine1: "CodexNotFound / AuthRequired / RateLimitUnavailable",
        .handledErrorsLine2: "ServerOverloaded (-32001) は自動リトライ",
        .troubleshootingOnly: "診断ビューはトラブルシューティング用です",
        .enabled: "有効",
        .disabled: "無効",
        .save: "保存",
        .visibleInMenu: "メニューバー表示",
        .noData: "データなし",
        .retention: "保持期間",
        .exportCSV: "CSV出力",
        .accountSignInRequired: "サインインが必要です",
        .currentSource: "現在のソース",
        .customPath: "codexカスタムパス",
        .appServerConnection: "App Server接続",
        .healthOk: "正常",
        .healthLoading: "読み込み中",
        .healthStale: "古い",
        .healthError: "エラー",
        .manualRefresh: "手動更新",
        .refreshing: "更新中",
        .refreshSuccess: "成功",
        .refreshFailed: "失敗",
        .menuAllLimits: "全リミット",
        .staleWarning: "データが古くなっています",
        .settings: "設定",
        .languageSystem: "システム",
        .languageEnglish: "英語",
        .languageJapanese: "日本語",
        .sourceAuto: "自動（Desktop優先）",
        .sourceApp: "Codex App",
        .sourceCLI: "Codex CLI",
        .sourceCustom: "カスタムパス",
        .snapshotsRange: "期間",
        .days7: "7日",
        .days30: "30日",
        .days90: "90日",
        .days180: "180日",
        .diagnosticsEmpty: "診断ログなし",
        .codexNotFound: "Codex コマンドが見つかりません",
        .authRequired: "認証が必要です",
        .comparePrevDay: "前日比",
        .shortStoragePolicy: "短期保存: Raw（5分間隔、固定28日）",
        .longStoragePolicy: "長期保存: Raw（GMT 00:00で日次）",
        .longTermRetention: "長期保持期間",
        .retentionOneYear: "1年",
        .retentionTwoYears: "2年",
        .retentionFiveYears: "5年",
        .retentionUnlimited: "無期限"
    ]
}
