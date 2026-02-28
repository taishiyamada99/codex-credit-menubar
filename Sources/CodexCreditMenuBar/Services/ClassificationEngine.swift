import Foundation

struct ClassificationEngine {
    func summarize(
        buckets: [LimitBucket],
        rules: [LimitAliasRule]
    ) -> [BucketSummary] {
        let grouped = Dictionary(grouping: buckets) { bucket in
            classify(bucket: bucket, rules: rules)
        }

        let summaries = grouped.compactMap { kind, values -> BucketSummary? in
            let sorted = values.sorted { $0.remainingPercent < $1.remainingPercent }
            guard let primary = sorted.first else {
                return nil
            }
            let secondary = sorted.count > 1 ? sorted[1] : nil
            let title: String
            switch kind {
            case .fiveHour:
                title = "5h"
            case .sevenDay:
                title = "7d"
            case .review:
                title = "Review"
            case .gptSpark:
                title = "GPT Spark"
            case .custom:
                title = primary.limitName
            }
            return BucketSummary(
                id: kind.rawValue,
                kind: kind,
                title: title,
                shortLabel: kind.shortLabel,
                primary: primary,
                secondary: secondary,
                members: sorted
            )
        }

        return summaries.sorted { lhs, rhs in
            order(of: lhs.kind) < order(of: rhs.kind)
        }
    }

    func classify(bucket: LimitBucket, rules: [LimitAliasRule]) -> BucketKind {
        let activeRules = rules
            .filter(\.enabled)
            .sorted { $0.priority < $1.priority }

        for rule in activeRules {
            let value = rule.field == .limitId ? bucket.limitId : bucket.limitName
            if matches(value: value, pattern: rule.pattern) {
                return rule.targetKind
            }
        }

        let id = bucket.limitId.lowercased()
        let name = bucket.limitName.lowercased()
        if id.contains("review") || name.contains("review") {
            return .review
        }
        if id.contains("spark") || name.contains("spark") || id.contains("bengalfox") {
            return .gptSpark
        }
        if id.contains("weekly") || name.contains("7 day") || name.contains("7-day") || name.contains("7d") {
            return .sevenDay
        }
        if name.contains("5 hour") || name.contains("5-hour") || name.contains("5h") {
            return .fiveHour
        }

        if let mins = bucket.windowDurationMins {
            if abs(mins - 300) <= 5 {
                return .fiveHour
            }
            if abs(mins - 10_080) <= 240 {
                return .sevenDay
            }
        }

        return .custom
    }

    private func matches(value: String, pattern: String) -> Bool {
        let target = value.lowercased()
        let regexPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !regexPattern.isEmpty else {
            return false
        }

        if let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: target.utf16.count)
            return regex.firstMatch(in: target, options: [], range: range) != nil
        }
        return target.contains(regexPattern.lowercased())
    }

    private func order(of kind: BucketKind) -> Int {
        switch kind {
        case .sevenDay:
            return 0
        case .fiveHour:
            return 1
        case .review:
            return 2
        case .gptSpark:
            return 3
        case .custom:
            return 4
        }
    }
}
