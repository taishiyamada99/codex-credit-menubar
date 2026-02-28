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
    case display
    case history
    case notifications
    case diagnostics
    case enabled
    case disabled
    case save
    case visibleInMenu
    case privacyMode
    case maxInline
    case aliasRules
    case addRule
    case noData
    case retention
    case exportCSV
    case requestNotification
    case thresholds
    case accountSignInRequired
    case currentSource
    case customPath
    case appServerConnection
    case healthOk
    case healthLoading
    case healthStale
    case healthError
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
    case rulePattern
    case ruleField
    case ruleTarget
    case rulePriority
    case remove
    case menuPrivacyMasked
    case snapshotsRange
    case days7
    case days30
    case days90
    case days180
    case diagnosticsEmpty
    case codexNotFound
    case authRequired
    case openNotificationSettings
    case comparePrevDay
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
        .display: "Display",
        .history: "History",
        .notifications: "Notifications",
        .diagnostics: "Diagnostics",
        .enabled: "Enabled",
        .disabled: "Disabled",
        .save: "Save",
        .visibleInMenu: "Visible in menu bar",
        .privacyMode: "Privacy mode",
        .maxInline: "Max inline items",
        .aliasRules: "Alias rules",
        .addRule: "Add Rule",
        .noData: "No data",
        .retention: "Retention",
        .exportCSV: "Export CSV",
        .requestNotification: "Request Notification Permission",
        .thresholds: "Thresholds",
        .accountSignInRequired: "Sign in required",
        .currentSource: "Current source",
        .customPath: "Custom codex path",
        .appServerConnection: "App Server Connection",
        .healthOk: "OK",
        .healthLoading: "Loading",
        .healthStale: "Stale",
        .healthError: "Error",
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
        .rulePattern: "Pattern",
        .ruleField: "Field",
        .ruleTarget: "Target",
        .rulePriority: "Priority",
        .remove: "Remove",
        .menuPrivacyMasked: "Hidden",
        .snapshotsRange: "Range",
        .days7: "7 days",
        .days30: "30 days",
        .days90: "90 days",
        .days180: "180 days",
        .diagnosticsEmpty: "No diagnostics",
        .codexNotFound: "Codex command not found",
        .authRequired: "Authentication required",
        .openNotificationSettings: "Open Notification Settings",
        .comparePrevDay: "vs prev day"
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
        .display: "表示",
        .history: "履歴",
        .notifications: "通知",
        .diagnostics: "診断",
        .enabled: "有効",
        .disabled: "無効",
        .save: "保存",
        .visibleInMenu: "メニューバー表示",
        .privacyMode: "プライバシーモード",
        .maxInline: "横並び最大件数",
        .aliasRules: "別名ルール",
        .addRule: "ルール追加",
        .noData: "データなし",
        .retention: "保持期間",
        .exportCSV: "CSV出力",
        .requestNotification: "通知許可を要求",
        .thresholds: "閾値",
        .accountSignInRequired: "サインインが必要です",
        .currentSource: "現在のソース",
        .customPath: "codexカスタムパス",
        .appServerConnection: "App Server接続",
        .healthOk: "正常",
        .healthLoading: "読み込み中",
        .healthStale: "古い",
        .healthError: "エラー",
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
        .rulePattern: "パターン",
        .ruleField: "対象フィールド",
        .ruleTarget: "分類先",
        .rulePriority: "優先度",
        .remove: "削除",
        .menuPrivacyMasked: "非表示",
        .snapshotsRange: "期間",
        .days7: "7日",
        .days30: "30日",
        .days90: "90日",
        .days180: "180日",
        .diagnosticsEmpty: "診断ログなし",
        .codexNotFound: "Codex コマンドが見つかりません",
        .authRequired: "認証が必要です",
        .openNotificationSettings: "通知設定を開く",
        .comparePrevDay: "前日比"
    ]
}
