import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor AppDatabase {
    private var db: OpaquePointer?
    private let dbURL: URL

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appDir = appSupport.appendingPathComponent("CodexCreditMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        dbURL = appDir.appendingPathComponent("codex_credits.sqlite")

        Self.openDatabase(at: dbURL, db: &db)
        Self.createTablesIfNeeded(db: db)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func loadSettings() -> AppSettings {
        guard let json = getSetting(key: AppSettings.settingsKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        setSetting(key: AppSettings.settingsKey, value: json)
    }

    func loadAliasRules() -> [LimitAliasRule] {
        let sql = """
        SELECT id, pattern, field, target_kind, enabled, priority
        FROM alias_rules
        ORDER BY priority ASC, id ASC;
        """
        guard let statement = prepare(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rules: [LimitAliasRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = stringValue(statement, index: 0)
            let pattern = stringValue(statement, index: 1)
            let fieldRaw = stringValue(statement, index: 2)
            let targetRaw = stringValue(statement, index: 3)
            let enabled = sqlite3_column_int(statement, 4) == 1
            let priority = Int(sqlite3_column_int(statement, 5))

            guard let uuid = UUID(uuidString: idString),
                  let field = AliasField(rawValue: fieldRaw),
                  let target = BucketKind(rawValue: targetRaw)
            else {
                continue
            }
            rules.append(LimitAliasRule(
                id: uuid,
                pattern: pattern,
                field: field,
                targetKind: target,
                enabled: enabled,
                priority: priority
            ))
        }
        return rules
    }

    func saveAliasRules(_ rules: [LimitAliasRule]) {
        exec(sql: "DELETE FROM alias_rules;")
        let insert = """
        INSERT INTO alias_rules(id, pattern, field, target_kind, enabled, priority)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql: insert) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for rule in rules {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, index: 1, value: rule.id.uuidString)
            bindText(statement, index: 2, value: rule.pattern)
            bindText(statement, index: 3, value: rule.field.rawValue)
            bindText(statement, index: 4, value: rule.targetKind.rawValue)
            sqlite3_bind_int(statement, 5, rule.enabled ? 1 : 0)
            sqlite3_bind_int(statement, 6, Int32(rule.priority))
            _ = sqlite3_step(statement)
        }
    }

    func saveSnapshotPoints(_ points: [SnapshotPoint]) {
        let sql = """
        INSERT OR REPLACE INTO snapshots(
            local_date, captured_at, kind, limit_id, remaining_percent, used_percent, source
        ) VALUES(?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for point in points {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, index: 1, value: point.dateLocal)
            sqlite3_bind_int64(statement, 2, Int64(point.capturedAt.timeIntervalSince1970))
            bindText(statement, index: 3, value: point.kind.rawValue)
            bindText(statement, index: 4, value: point.limitId)
            sqlite3_bind_double(statement, 5, point.remainingPercent)
            if let usedPercent = point.usedPercent {
                sqlite3_bind_double(statement, 6, usedPercent)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            bindText(statement, index: 7, value: point.source.rawValue)
            _ = sqlite3_step(statement)
        }
    }

    func fetchSnapshots(days: Int, kinds: Set<BucketKind>) -> [SnapshotPoint] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -max(1, days), to: Date()) ?? Date()
        let cutoffKey = DateUtils.localDateKey(from: cutoffDate)

        var sql = """
        SELECT local_date, captured_at, kind, limit_id, remaining_percent, used_percent, source
        FROM snapshots
        WHERE local_date >= ?
        """

        let requestedKinds = kinds.isEmpty ? BucketKind.allCases : Array(kinds)
        if !requestedKinds.isEmpty {
            let placeholders = Array(repeating: "?", count: requestedKinds.count).joined(separator: ",")
            sql += " AND kind IN (\(placeholders))"
        }
        sql += " ORDER BY local_date ASC, kind ASC;"

        guard let statement = prepare(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: cutoffKey)
        for (index, kind) in requestedKinds.enumerated() {
            bindText(statement, index: Int32(index + 2), value: kind.rawValue)
        }

        var points: [SnapshotPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let localDate = stringValue(statement, index: 0)
            let capturedAtEpoch = sqlite3_column_int64(statement, 1)
            let kindRaw = stringValue(statement, index: 2)
            let limitID = stringValue(statement, index: 3)
            let remaining = sqlite3_column_double(statement, 4)
            let usedPercent: Double?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                usedPercent = nil
            } else {
                usedPercent = sqlite3_column_double(statement, 5)
            }
            let sourceRaw = stringValue(statement, index: 6)

            guard let kind = BucketKind(rawValue: kindRaw),
                  let source = SnapshotSource(rawValue: sourceRaw)
            else {
                continue
            }

            let captured = Date(timeIntervalSince1970: TimeInterval(capturedAtEpoch))
            points.append(SnapshotPoint(
                id: "\(localDate)-\(kindRaw)-\(limitID)",
                dateLocal: localDate,
                capturedAt: captured,
                kind: kind,
                limitId: limitID,
                remainingPercent: remaining,
                usedPercent: usedPercent,
                source: source
            ))
        }

        return points
    }

    func pruneSnapshots(olderThanDays days: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -max(1, days), to: Date()) ?? Date()
        let cutoffKey = DateUtils.localDateKey(from: cutoffDate)
        let sql = "DELETE FROM snapshots WHERE local_date < ?;"
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: cutoffKey)
        _ = sqlite3_step(statement)
    }

    func wasThresholdNotified(limitId: String, resetAt: Date, threshold: Int) -> Bool {
        let sql = """
        SELECT 1 FROM notify_state
        WHERE limit_id = ? AND reset_at = ? AND threshold = ?
        LIMIT 1;
        """
        guard let statement = prepare(sql: sql) else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: limitId)
        sqlite3_bind_int64(statement, 2, Int64(resetAt.timeIntervalSince1970))
        sqlite3_bind_int(statement, 3, Int32(threshold))

        return sqlite3_step(statement) == SQLITE_ROW
    }

    func markThresholdNotified(limitId: String, resetAt: Date, threshold: Int) {
        let sql = """
        INSERT OR IGNORE INTO notify_state(limit_id, reset_at, threshold, notified_at)
        VALUES (?, ?, ?, ?);
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: limitId)
        sqlite3_bind_int64(statement, 2, Int64(resetAt.timeIntervalSince1970))
        sqlite3_bind_int(statement, 3, Int32(threshold))
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        _ = sqlite3_step(statement)
    }

    func appendDiagnostic(level: String, code: String, message: String) {
        let sql = """
        INSERT INTO diagnostic_events(level, code, message, created_at)
        VALUES(?, ?, ?, ?);
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: level)
        bindText(statement, index: 2, value: code)
        bindText(statement, index: 3, value: message)
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        _ = sqlite3_step(statement)
    }

    func fetchDiagnostics(limit: Int = 200) -> [DiagnosticEvent] {
        let sql = """
        SELECT id, level, code, message, created_at
        FROM diagnostic_events
        ORDER BY id DESC
        LIMIT ?;
        """
        guard let statement = prepare(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var items: [DiagnosticEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let level = stringValue(statement, index: 1)
            let code = stringValue(statement, index: 2)
            let message = stringValue(statement, index: 3)
            let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))
            items.append(DiagnosticEvent(id: id, level: level, code: code, message: message, createdAt: createdAt))
        }

        return items
    }

    private static func openDatabase(at dbURL: URL, db: inout OpaquePointer?) {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private static func createTablesIfNeeded(db: OpaquePointer?) {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS alias_rules(
                id TEXT PRIMARY KEY,
                pattern TEXT NOT NULL,
                field TEXT NOT NULL,
                target_kind TEXT NOT NULL,
                enabled INTEGER NOT NULL,
                priority INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS snapshots(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                local_date TEXT NOT NULL,
                captured_at INTEGER NOT NULL,
                kind TEXT NOT NULL,
                limit_id TEXT,
                remaining_percent REAL NOT NULL,
                used_percent REAL,
                source TEXT NOT NULL,
                UNIQUE(local_date, kind, limit_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS notify_state(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                limit_id TEXT NOT NULL,
                reset_at INTEGER NOT NULL,
                threshold INTEGER NOT NULL,
                notified_at INTEGER NOT NULL,
                UNIQUE(limit_id, reset_at, threshold)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS diagnostic_events(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                level TEXT NOT NULL,
                code TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            """
        ]

        for statement in statements {
            exec(db: db, sql: statement)
        }
    }

    private static func exec(db: OpaquePointer?, sql: String) {
        guard let db else {
            return
        }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func getSetting(key: String) -> String? {
        let sql = "SELECT value FROM settings WHERE key = ? LIMIT 1;"
        guard let statement = prepare(sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: key)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return stringValue(statement, index: 0)
    }

    private func setSetting(key: String, value: String) {
        let sql = """
        INSERT INTO settings(key, value, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at;
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: key)
        bindText(statement, index: 2, value: value)
        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
        _ = sqlite3_step(statement)
    }

    private func exec(sql: String) {
        guard let db else {
            return
        }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(sql: String) -> OpaquePointer? {
        guard let db else {
            return nil
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        return statement
    }

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func stringValue(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }
}
