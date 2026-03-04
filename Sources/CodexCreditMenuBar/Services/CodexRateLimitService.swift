import Foundation

actor CodexRateLimitService: RateLimitProvider {
    nonisolated let stream: AsyncStream<ServiceEvent>
    private let streamContinuation: AsyncStream<ServiceEvent>.Continuation

    private var settings: AppSettings
    private let resolver = SourceResolver()
    private var client: AppServerClient?
    private var running = false
    private var reconnectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var reconnectBackoffIndex = 0
    private var selectedCommand: CodexCommand?
    private var lastRefreshSignature: String?
    private var isRefreshing = false
    private var queuedRefreshTrigger: String?
    private var lastRepeatedLogByCode: [String: (message: String, at: Date)] = [:]

    private let reconnectBackoffSeconds = [5, 15, 30, 60, 300]
    private let diagnostics: @Sendable (String, String, String) -> Void

    init(settings: AppSettings, diagnostics: @escaping @Sendable (String, String, String) -> Void) {
        self.settings = settings
        self.diagnostics = diagnostics
        var continuation: AsyncStream<ServiceEvent>.Continuation!
        self.stream = AsyncStream<ServiceEvent> { streamContinuation in
            continuation = streamContinuation
        }
        self.streamContinuation = continuation
    }

    func start() async {
        guard !running else {
            return
        }
        running = true
        publish(.state(ServiceState.initial))
        await connect()
    }

    func stop() async {
        running = false
        pollTask?.cancel()
        reconnectTask?.cancel()
        pollTask = nil
        reconnectTask = nil
        if let client {
            await client.stop()
        }
        client = nil
        selectedCommand = nil
    }

    func applySettings(_ settings: AppSettings) async {
        let sourceChanged = self.settings.sourceMode != settings.sourceMode || self.settings.customCodexPath != settings.customCodexPath
        let refreshChanged = self.settings.refreshIntervalMinutes != settings.refreshIntervalMinutes

        self.settings = settings

        if refreshChanged {
            restartPolling()
        }

        if sourceChanged {
            diagnostics("info", "source_changed", "Source mode changed, reconnecting")
            await reconnect(reason: "source changed")
        }
    }

    func refreshNow() async {
        await performRefresh(trigger: "manual")
    }

    private func connect() async {
        guard running else {
            return
        }

        reconnectTask?.cancel()

        let commands = resolver.resolve(mode: settings.sourceMode, customPath: settings.customCodexPath)
        guard !commands.isEmpty else {
            publish(.state(ServiceState(
                sourceLabel: "-",
                status: .error,
                lastUpdatedAt: nil,
                buckets: [],
                message: L10n.text(.codexNotFound, languageMode: settings.languageMode),
                authRequired: false
            )))
            diagnostics("error", "codex_not_found", "No candidate command resolved")
            return
        }

        for command in commands {
            guard running else {
                return
            }

            diagnostics("info", "connect_attempt", "Trying \(command.label): \(command.launchPath)")
            do {
                let client = AppServerClient(command: command)
                await client.configureHandlers(onNotification: { [weak self] method, params in
                    Task {
                        await self?.handleNotification(method: method, params: params)
                    }
                }, onDisconnect: { [weak self] reason in
                    Task {
                        await self?.handleDisconnect(reason: reason)
                    }
                })

                try await client.start()
                try await initialize(client: client)

                self.client = client
                selectedCommand = command
                reconnectBackoffIndex = 0

                diagnostics("info", "connect_success", "Connected using \(command.label)")

                await performRefresh(trigger: "initial")
                restartPolling()
                return
            } catch {
                diagnostics("error", "connect_failed", "Failed with \(command.label): \(error.localizedDescription)")
                continue
            }
        }

        publish(.state(ServiceState(
            sourceLabel: "-",
            status: .error,
            lastUpdatedAt: nil,
            buckets: [],
            message: L10n.text(.codexNotFound, languageMode: settings.languageMode),
            authRequired: false
        )))
    }

    private func initialize(client: AppServerClient) async throws {
        _ = try await client.request(method: "initialize", params: [
            "protocolVersion": "2025-06-18",
            "clientInfo": [
                "name": "CodexCreditMenuBar",
                "version": "0.1.0"
            ],
            "capabilities": [:]
        ])
        try await client.notify(method: "initialized", params: [:])
    }

    private func performRefresh(trigger: String) async {
        guard running else {
            return
        }

        if isRefreshing {
            if trigger == "manual" {
                queuedRefreshTrigger = "manual"
            } else if queuedRefreshTrigger == nil {
                queuedRefreshTrigger = trigger
            }
            return
        }
        isRefreshing = true

        guard let client else {
            await reconnect(reason: "refresh_while_disconnected")
            await finishRefreshAndDrainQueue()
            return
        }

        do {
            let accountResult = try await client.request(method: "account/read")
            let authRequired = parseAuthRequired(accountResult)
            if authRequired {
                publish(.state(ServiceState(
                    sourceLabel: selectedCommand?.label ?? "-",
                    status: .error,
                    lastUpdatedAt: nil,
                    buckets: [],
                    message: L10n.text(.authRequired, languageMode: settings.languageMode),
                    authRequired: true
                )))
                diagnostics("warn", "auth_required", "account/read returned unauthenticated state")
            } else {
                let rateLimitResult = try await client.request(method: "account/rateLimits/read")
                var buckets = parseRateLimits(result: rateLimitResult)

                if buckets.isEmpty {
                    buckets = parseRateLimits(result: accountResult)
                }

                if buckets.isEmpty {
                    diagnostics("warn", "empty_rate_limits", "No rate limits parsed on \(trigger)")
                }

                let now = Date()
                let state = ServiceState(
                    sourceLabel: selectedCommand?.label ?? "-",
                    status: .ok,
                    lastUpdatedAt: now,
                    buckets: buckets,
                    message: nil,
                    authRequired: false
                )
                publish(.state(state))
                let preview = buckets.prefix(4).map { bucket in
                    "\(bucket.limitId)=\(Int(bucket.remainingPercent.rounded()))%"
                }.joined(separator: ", ")
                let signature = buckets
                    .map { "\($0.limitId):\(Int($0.remainingPercent.rounded())):\($0.windowDurationMins ?? -1)" }
                    .sorted()
                    .joined(separator: "|")
                if trigger != "timer" || signature != lastRefreshSignature {
                    diagnostics("info", "refresh_success", "trigger=\(trigger) buckets=\(buckets.count) [\(preview)]")
                    lastRefreshSignature = signature
                }
            }
        } catch {
            diagnostics("error", "refresh_failed", "Refresh failed (\(trigger)): \(error.localizedDescription)")
            publish(.state(ServiceState(
                sourceLabel: selectedCommand?.label ?? "-",
                status: .error,
                lastUpdatedAt: nil,
                buckets: [],
                message: error.localizedDescription,
                authRequired: false
            )))
            await reconnect(reason: "refresh_failed")
        }
        await finishRefreshAndDrainQueue()
    }

    private func finishRefreshAndDrainQueue() async {
        isRefreshing = false
        guard let queued = queuedRefreshTrigger else {
            return
        }
        queuedRefreshTrigger = nil
        await performRefresh(trigger: queued)
    }

    private func parseAuthRequired(_ result: Any) -> Bool {
        guard let dict = result as? [String: Any] else {
            return false
        }

        if let loggedIn = dict["loggedIn"] as? Bool {
            return !loggedIn
        }
        if let isAuthenticated = dict["isAuthenticated"] as? Bool {
            return !isAuthenticated
        }
        if let status = (dict["authStatus"] as? String)?.lowercased() {
            return status.contains("logged_out") || status.contains("unauth") || status.contains("required")
        }

        if let account = dict["account"] {
            return parseAuthRequired(account)
        }

        return false
    }

    func parseRateLimits(result: Any) -> [LimitBucket] {
        guard let dict = result as? [String: Any] else {
            return []
        }

        if let byID = dict["rateLimitsByLimitId"] as? [String: Any] {
            let buckets = byID.flatMap { key, value -> [LimitBucket] in
                guard let item = value as? [String: Any] else {
                    return []
                }
                return parseLimitBuckets(limitId: key, payload: item)
            }
            if !buckets.isEmpty {
                return buckets
            }
        }

        if let one = dict["rateLimits"] as? [String: Any] {
            let limitId = (one["limitId"] as? String) ?? (one["id"] as? String) ?? "codex"
            return parseLimitBuckets(limitId: limitId, payload: one)
        }

        if let array = dict["rateLimits"] as? [Any] {
            let buckets = array.flatMap { item -> [LimitBucket] in
                guard let payload = item as? [String: Any] else {
                    return []
                }
                let limitId = (payload["limitId"] as? String) ?? (payload["id"] as? String) ?? UUID().uuidString
                return parseLimitBuckets(limitId: limitId, payload: payload)
            }
            if !buckets.isEmpty {
                return buckets
            }
        }

        if let nested = dict["result"] {
            return parseRateLimits(result: nested)
        }

        if let nested = dict["account"] {
            return parseRateLimits(result: nested)
        }

        if dict["limitId"] != nil || dict["primary"] != nil {
            let limitId = (dict["limitId"] as? String) ?? (dict["id"] as? String) ?? "codex"
            return parseLimitBuckets(limitId: limitId, payload: dict)
        }

        return []
    }

    private func parseLimitBuckets(limitId: String, payload: [String: Any]) -> [LimitBucket] {
        let primaryBucket = parseOneLimit(limitId: limitId, payload: payload)
        let limitName = (payload["limitName"] as? String) ?? (payload["name"] as? String) ?? limitId
        guard let secondaryPart = payload["secondary"] as? [String: Any] else {
            return [primaryBucket]
        }
        let secondaryBucket = parseLimitPart(
            limitId: limitId,
            limitName: limitName,
            part: secondaryPart,
            fallback: payload,
            hasSecondary: false
        )
        return [primaryBucket, secondaryBucket]
    }

    func parseOneLimit(limitId: String, payload: [String: Any]) -> LimitBucket {
        let limitName = (payload["limitName"] as? String) ?? (payload["name"] as? String) ?? limitId
        let hasSecondary = payload["secondary"] as? [String: Any] != nil
        if let primaryPart = payload["primary"] as? [String: Any] {
            return parseLimitPart(
                limitId: limitId,
                limitName: limitName,
                part: primaryPart,
                fallback: payload,
                hasSecondary: hasSecondary
            )
        }

        return parseLimitPart(
            limitId: limitId,
            limitName: limitName,
            part: payload,
            fallback: nil,
            hasSecondary: hasSecondary
        )
    }

    private func parseLimitPart(
        limitId: String,
        limitName: String,
        part: [String: Any],
        fallback: [String: Any]?,
        hasSecondary: Bool
    ) -> LimitBucket {
        let usedPercent = parseUsedPercent(part: part, fallback: fallback)
        let remaining = clampPercent(100 - usedPercent)
        let window = Self.intValue(part["windowDurationMins"])
            ?? Self.intValue(part["windowDurationMinutes"])
            ?? Self.intValue(fallback?["windowDurationMins"])
            ?? Self.intValue(fallback?["windowDurationMinutes"])
        let resetAt = DateUtils.parseFlexibleDate(
            part["resetsAt"]
                ?? part["resetAt"]
                ?? fallback?["resetsAt"]
                ?? fallback?["resetAt"]
        )
        let updatedAt = DateUtils.parseFlexibleDate(
            part["updatedAt"]
                ?? part["lastUpdatedAt"]
                ?? fallback?["updatedAt"]
                ?? fallback?["lastUpdatedAt"]
        )

        return LimitBucket(
            limitId: limitId,
            limitName: limitName,
            usedPercent: usedPercent,
            remainingPercent: remaining,
            windowDurationMins: window,
            resetsAt: resetAt,
            updatedAt: updatedAt,
            hasSecondary: hasSecondary
        )
    }

    private func parseUsedPercent(part: [String: Any], fallback: [String: Any]?) -> Double {
        if let value = Self.doubleValue(part["usedPercent"])
            ?? Self.doubleValue(part["usagePercent"])
            ?? Self.doubleValue(fallback?["usedPercent"])
            ?? Self.doubleValue(fallback?["usagePercent"]) {
            return clampPercent(value)
        }

        if let remaining = Self.doubleValue(part["remainingPercent"])
            ?? Self.doubleValue(fallback?["remainingPercent"]) {
            return clampPercent(100 - remaining)
        }

        let usedCount = Self.doubleValue(part["used"])
            ?? Self.doubleValue(part["usedCount"])
            ?? Self.doubleValue(fallback?["used"])
            ?? Self.doubleValue(fallback?["usedCount"])
        let totalCount = Self.doubleValue(part["limit"])
            ?? Self.doubleValue(part["max"])
            ?? Self.doubleValue(part["total"])
            ?? Self.doubleValue(fallback?["limit"])
            ?? Self.doubleValue(fallback?["max"])
            ?? Self.doubleValue(fallback?["total"])

        if let usedCount, let totalCount, totalCount > 0 {
            return clampPercent((usedCount / totalCount) * 100)
        }

        return 0
    }

    private func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        guard let any else {
            return nil
        }
        if let value = any as? Double {
            return value
        }
        if let value = any as? Float {
            return Double(value)
        }
        if let value = any as? Int {
            return Double(value)
        }
        if let value = any as? NSNumber {
            return value.doubleValue
        }
        if let value = any as? String {
            return Double(value)
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        guard let any else {
            return nil
        }
        if let value = any as? Int {
            return value
        }
        if let value = any as? NSNumber {
            return value.intValue
        }
        if let value = any as? String {
            return Int(value)
        }
        return nil
    }

    private func restartPolling() {
        pollTask?.cancel()
        guard running else {
            return
        }
        let minutes = max(1, settings.refreshIntervalMinutes)
        pollTask = Task {
            while !Task.isCancelled {
                let sleepNs = UInt64(minutes * 60) * 1_000_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
                if Task.isCancelled {
                    break
                }
                await self.performRefresh(trigger: "timer")
            }
        }
    }

    private func handleNotification(method: String, params: [String: Any]?) async {
        if method == "account/rateLimits/updated" || method == "account/updated" {
            let notificationLog = "Received \(method)"
            if shouldLogRepeated(code: "server_notification", message: notificationLog, minInterval: 30) {
                diagnostics("info", "server_notification", notificationLog)
            }
            await performRefresh(trigger: method)
        } else if method == "stderr" {
            let message = (params?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.isEmpty {
                let stderrLog = "Received stderr output"
                if shouldLogRepeated(code: "server_stderr", message: stderrLog, minInterval: 30) {
                    diagnostics("debug", "server_stderr", stderrLog)
                }
            } else {
                if shouldLogRepeated(code: "server_stderr", message: message, minInterval: 30) {
                    diagnostics("debug", "server_stderr", message)
                }
            }
        }
    }

    private func handleDisconnect(reason: String) async {
        diagnostics("warn", "disconnected", reason)
        publish(.state(ServiceState(
            sourceLabel: selectedCommand?.label ?? "-",
            status: .error,
            lastUpdatedAt: nil,
            buckets: [],
            message: reason,
            authRequired: false
        )))
        await reconnect(reason: reason)
    }

    private func reconnect(reason: String) async {
        guard running else {
            return
        }

        reconnectTask?.cancel()
        let delay = nextReconnectDelay()
        diagnostics("info", "reconnect_scheduled", "in \(delay)s because \(reason)")
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            if Task.isCancelled {
                return
            }
            await self.performReconnect()
        }
    }

    private func nextReconnectDelay() -> Int {
        let index = min(reconnectBackoffIndex, reconnectBackoffSeconds.count - 1)
        let delay = reconnectBackoffSeconds[index]
        if reconnectBackoffIndex < reconnectBackoffSeconds.count - 1 {
            reconnectBackoffIndex += 1
        }
        return delay
    }

    private func performReconnect() async {
        guard running else {
            return
        }
        await client?.stop()
        client = nil
        await connect()
    }

    private func publish(_ event: ServiceEvent) {
        streamContinuation.yield(event)
    }

    private func shouldLogRepeated(code: String, message: String, minInterval: TimeInterval) -> Bool {
        let now = Date()
        if let previous = lastRepeatedLogByCode[code],
           previous.message == message,
           now.timeIntervalSince(previous.at) < minInterval {
            return false
        }
        lastRepeatedLogByCode[code] = (message, now)
        return true
    }
}
