import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor AppDatabase {
    private var db: OpaquePointer?
    private let dbURL: URL
    private var diagnosticInsertCountSincePrune = 0
    private let maxDiagnosticRows = 2_000
    private let diagnosticPruneInterval = 50

    init(databaseURL: URL? = nil) {
        let fileManager = FileManager.default
        if let databaseURL {
            let directory = databaseURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            dbURL = databaseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let appDir = appSupport.appendingPathComponent("CodexCreditMenuBar", isDirectory: true)
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
            dbURL = appDir.appendingPathComponent("codex_credits.sqlite")
        }

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

    func saveShortRawSamples(slotEpoch: Int64, capturedAt: Date, samples: [RawBucketSample]) {
        guard !samples.isEmpty else {
            return
        }
        let sql = """
        INSERT OR REPLACE INTO short_samples_raw(
            slot_epoch, captured_at, limit_id, limit_name, kind, remaining_percent, used_percent, resets_at, source
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for sample in samples {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, slotEpoch)
            sqlite3_bind_int64(statement, 2, Int64(capturedAt.timeIntervalSince1970))
            bindText(statement, index: 3, value: sample.limitId)
            bindText(statement, index: 4, value: sample.limitName)
            bindText(statement, index: 5, value: sample.kind.rawValue)
            sqlite3_bind_double(statement, 6, sample.remainingPercent)
            sqlite3_bind_double(statement, 7, sample.usedPercent)
            if let resetsAt = sample.resetsAt {
                sqlite3_bind_int64(statement, 8, Int64(resetsAt.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(statement, 8)
            }
            bindText(statement, index: 9, value: sample.source.rawValue)
            _ = sqlite3_step(statement)
        }
    }

    func pruneShortRawSamples(olderThanSlotEpoch slotEpoch: Int64) {
        let sql = "DELETE FROM short_samples_raw WHERE slot_epoch < ?;"
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, slotEpoch)
        _ = sqlite3_step(statement)
    }

    func countShortRawSamples(slotEpoch: Int64) -> Int {
        let sql = "SELECT COUNT(*) FROM short_samples_raw WHERE slot_epoch = ?;"
        guard let statement = prepare(sql: sql) else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, slotEpoch)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func saveLongTermRawDaily(dayKeyGMT: String, capturedAt: Date, samples: [RawBucketSample]) {
        guard !samples.isEmpty else {
            return
        }
        let sql = """
        INSERT OR REPLACE INTO long_term_raw_daily(
            day_key_gmt, captured_at, limit_id, limit_name, kind, remaining_percent, used_percent, resets_at, source
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for sample in samples {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, index: 1, value: dayKeyGMT)
            sqlite3_bind_int64(statement, 2, Int64(capturedAt.timeIntervalSince1970))
            bindText(statement, index: 3, value: sample.limitId)
            bindText(statement, index: 4, value: sample.limitName)
            bindText(statement, index: 5, value: sample.kind.rawValue)
            sqlite3_bind_double(statement, 6, sample.remainingPercent)
            sqlite3_bind_double(statement, 7, sample.usedPercent)
            if let resetsAt = sample.resetsAt {
                sqlite3_bind_int64(statement, 8, Int64(resetsAt.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(statement, 8)
            }
            bindText(statement, index: 9, value: sample.source.rawValue)
            _ = sqlite3_step(statement)
        }
    }

    func pruneLongTermRawDaily(retention: LongTermRetention, now: Date = Date()) {
        guard let retentionDays = retention.retentionDays else {
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        let cutoffDayKey = DateUtils.gmtDateKey(from: cutoffDate)
        let sql = "DELETE FROM long_term_raw_daily WHERE day_key_gmt < ?;"
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: cutoffDayKey)
        _ = sqlite3_step(statement)
    }

    func countLongTermRawSamples(dayKeyGMT: String) -> Int {
        let sql = "SELECT COUNT(*) FROM long_term_raw_daily WHERE day_key_gmt = ?;"
        guard let statement = prepare(sql: sql) else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: dayKeyGMT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func fetchShortRawHistory(fromSlotEpoch slotEpoch: Int64, kinds: Set<BucketKind>) -> [SnapshotPoint] {
        var sql = """
        SELECT slot_epoch, kind, MIN(remaining_percent), MAX(used_percent),
               MAX(CASE WHEN source = 'exact' THEN 1 ELSE 0 END)
        FROM short_samples_raw
        WHERE slot_epoch >= ?
        """
        let requestedKinds = kinds.isEmpty ? BucketKind.allCases : Array(kinds)
        if !requestedKinds.isEmpty {
            let placeholders = Array(repeating: "?", count: requestedKinds.count).joined(separator: ",")
            sql += " AND kind IN (\(placeholders))"
        }
        sql += " GROUP BY slot_epoch, kind ORDER BY slot_epoch ASC, kind ASC;"

        guard let statement = prepare(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, slotEpoch)
        for (index, kind) in requestedKinds.enumerated() {
            bindText(statement, index: Int32(index + 2), value: kind.rawValue)
        }

        var points: [SnapshotPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let slot = sqlite3_column_int64(statement, 0)
            let kindRaw = stringValue(statement, index: 1)
            let remaining = sqlite3_column_double(statement, 2)
            let usedPercent: Double?
            if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                usedPercent = nil
            } else {
                usedPercent = sqlite3_column_double(statement, 3)
            }
            let hasExact = sqlite3_column_int(statement, 4) == 1
            guard let kind = BucketKind(rawValue: kindRaw) else {
                continue
            }
            let capturedAt = Date(timeIntervalSince1970: TimeInterval(slot))
            let source: SnapshotSource = hasExact ? .exact : .carriedForward
            points.append(SnapshotPoint(
                id: "short-\(slot)-\(kind.rawValue)",
                dateLocal: DateUtils.localDateKey(from: capturedAt),
                capturedAt: capturedAt,
                kind: kind,
                limitId: "\(kind.rawValue)-short",
                remainingPercent: remaining,
                usedPercent: usedPercent,
                source: source
            ))
        }
        return points
    }

    func fetchLongTermRawHistory(fromDayKeyGMT dayKeyGMT: String, kinds: Set<BucketKind>) -> [SnapshotPoint] {
        var sql = """
        SELECT day_key_gmt, kind, MIN(remaining_percent), MAX(used_percent),
               MAX(CASE WHEN source = 'exact' THEN 1 ELSE 0 END), MIN(captured_at)
        FROM long_term_raw_daily
        WHERE day_key_gmt >= ?
        """
        let requestedKinds = kinds.isEmpty ? BucketKind.allCases : Array(kinds)
        if !requestedKinds.isEmpty {
            let placeholders = Array(repeating: "?", count: requestedKinds.count).joined(separator: ",")
            sql += " AND kind IN (\(placeholders))"
        }
        sql += " GROUP BY day_key_gmt, kind ORDER BY day_key_gmt ASC, kind ASC;"

        guard let statement = prepare(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: dayKeyGMT)
        for (index, kind) in requestedKinds.enumerated() {
            bindText(statement, index: Int32(index + 2), value: kind.rawValue)
        }

        var points: [SnapshotPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let dayKey = stringValue(statement, index: 0)
            let kindRaw = stringValue(statement, index: 1)
            let remaining = sqlite3_column_double(statement, 2)
            let usedPercent: Double?
            if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                usedPercent = nil
            } else {
                usedPercent = sqlite3_column_double(statement, 3)
            }
            let hasExact = sqlite3_column_int(statement, 4) == 1
            let capturedAtEpoch = sqlite3_column_int64(statement, 5)
            guard let kind = BucketKind(rawValue: kindRaw) else {
                continue
            }
            let capturedAt: Date
            if capturedAtEpoch > 0 {
                capturedAt = Date(timeIntervalSince1970: TimeInterval(capturedAtEpoch))
            } else {
                capturedAt = DateUtils.dateFromGMTDateKey(dayKey) ?? Date()
            }
            let source: SnapshotSource = hasExact ? .exact : .carriedForward
            points.append(SnapshotPoint(
                id: "long-\(dayKey)-\(kind.rawValue)",
                dateLocal: dayKey,
                capturedAt: capturedAt,
                kind: kind,
                limitId: "\(kind.rawValue)-long",
                remainingPercent: remaining,
                usedPercent: usedPercent,
                source: source
            ))
        }
        return points
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

        diagnosticInsertCountSincePrune += 1
        if diagnosticInsertCountSincePrune >= diagnosticPruneInterval {
            diagnosticInsertCountSincePrune = 0
            pruneDiagnostics(maxRows: maxDiagnosticRows)
        }
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
        // Alias-rules feature has been removed; clean up legacy table if present.
        exec(db: db, sql: "DROP TABLE IF EXISTS alias_rules;")
        // Notification feature has been removed; clean up legacy table if present.
        exec(db: db, sql: "DROP TABLE IF EXISTS notify_state;")

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
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
            CREATE TABLE IF NOT EXISTS short_samples_raw(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                slot_epoch INTEGER NOT NULL,
                captured_at INTEGER NOT NULL,
                limit_id TEXT NOT NULL,
                limit_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                remaining_percent REAL NOT NULL,
                used_percent REAL,
                resets_at INTEGER,
                source TEXT NOT NULL,
                UNIQUE(slot_epoch, limit_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS long_term_raw_daily(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                day_key_gmt TEXT NOT NULL,
                captured_at INTEGER NOT NULL,
                limit_id TEXT NOT NULL,
                limit_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                remaining_percent REAL NOT NULL,
                used_percent REAL,
                resets_at INTEGER,
                source TEXT NOT NULL,
                UNIQUE(day_key_gmt, limit_id)
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_short_slot_epoch ON short_samples_raw(slot_epoch);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_long_day_key ON long_term_raw_daily(day_key_gmt);
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

    private func pruneDiagnostics(maxRows: Int) {
        let sql = """
        DELETE FROM diagnostic_events
        WHERE id NOT IN (
            SELECT id
            FROM diagnostic_events
            ORDER BY id DESC
            LIMIT ?
        );
        """
        guard let statement = prepare(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(maxRows))
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
