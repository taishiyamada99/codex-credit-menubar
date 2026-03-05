import Foundation

enum DateUtils {
    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let gmtDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let gmtCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()

    static func localDateKey(from date: Date = Date()) -> String {
        localDayFormatter.string(from: date)
    }

    static func dateFromLocalDateKey(_ key: String) -> Date? {
        localDayFormatter.date(from: key)
    }

    static func gmtDateKey(from date: Date = Date()) -> String {
        gmtDayFormatter.string(from: date)
    }

    static func dateFromGMTDateKey(_ key: String) -> Date? {
        gmtDayFormatter.date(from: key)
    }

    static func nextGMTMidnight(from date: Date = Date()) -> Date {
        var next = gmtCalendar.date(
            bySettingHour: 0,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
        if next <= date {
            next = gmtCalendar.date(byAdding: .day, value: 1, to: next) ?? date
        }
        return next
    }

    static func fiveMinuteSlotEpoch(from date: Date = Date()) -> Int64 {
        let epoch = Int64(date.timeIntervalSince1970)
        return epoch - (epoch % 300)
    }

    static func nextFiveMinuteBoundary(from date: Date = Date()) -> Date {
        let slot = fiveMinuteSlotEpoch(from: date)
        return Date(timeIntervalSince1970: TimeInterval(slot + 300))
    }

    static func isStale(lastUpdated: Date?, thresholdMinutes: Int = 15) -> Bool {
        guard let lastUpdated else {
            return true
        }
        return Date().timeIntervalSince(lastUpdated) > Double(thresholdMinutes * 60)
    }

    static func nowPastSnapshotTime(hour: Int = 2) -> Bool {
        let now = Date()
        let currentHour = Calendar.current.component(.hour, from: now)
        return currentHour >= hour
    }

    static func nextSnapshotDate(hour: Int = 2) -> Date {
        let now = Date()
        var next = Calendar.current.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        if next <= now {
            next = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? now
        }
        return next
    }

    static func parseFlexibleDate(_ value: Any?) -> Date? {
        guard let value else {
            return nil
        }

        if let date = value as? Date {
            return date
        }

        if let timestamp = value as? TimeInterval {
            if timestamp > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            return Date(timeIntervalSince1970: timestamp)
        }

        if let number = value as? NSNumber {
            let double = number.doubleValue
            if double > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: double / 1000)
            }
            return Date(timeIntervalSince1970: double)
        }

        if let string = value as? String {
            let isoParsers = [
                ISO8601DateFormatter(),
                ISO8601DateFormatter()
            ]
            isoParsers[1].formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for parser in isoParsers {
                if let parsed = parser.date(from: string) {
                    return parsed
                }
            }
            if let double = Double(string) {
                if double > 1_000_000_000_000 {
                    return Date(timeIntervalSince1970: double / 1000)
                }
                return Date(timeIntervalSince1970: double)
            }
        }

        return nil
    }

    static func displayPercent(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }
}
