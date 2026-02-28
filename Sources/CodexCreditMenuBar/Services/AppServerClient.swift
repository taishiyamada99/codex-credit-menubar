import Foundation

enum AppServerError: LocalizedError {
    case processLaunchFailed(String)
    case notConnected
    case invalidResponse
    case rpc(code: Int, message: String)
    case missingResult

    var errorDescription: String? {
        switch self {
        case let .processLaunchFailed(message):
            return "Process launch failed: \(message)"
        case .notConnected:
            return "App server is not connected"
        case .invalidResponse:
            return "Invalid app server response"
        case let .rpc(code, message):
            return "RPC error (\(code)): \(message)"
        case .missingResult:
            return "Missing result"
        }
    }
}

actor AppServerClient {
    typealias NotificationHandler = @Sendable (String, [String: Any]?) -> Void
    typealias DisconnectHandler = @Sendable (String) -> Void

    private let command: CodexCommand
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var incomingBuffer = Data()
    private var expectedBodyLength: Int?
    private var pendingRequests: [Int: CheckedContinuation<Any, Error>] = [:]
    private var requestID = 0

    private var onNotification: NotificationHandler?
    private var onDisconnect: DisconnectHandler?

    init(command: CodexCommand) {
        self.command = command
    }

    func configureHandlers(
        onNotification: NotificationHandler?,
        onDisconnect: DisconnectHandler?
    ) {
        self.onNotification = onNotification
        self.onDisconnect = onDisconnect
    }

    func start() async throws {
        if process != nil {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.launchPath)
        process.arguments = command.arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleProcessTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            throw AppServerError.processLaunchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                Task {
                    await self?.handleProcessTermination(status: 0)
                }
                return
            }
            Task {
                await self?.appendIncomingData(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                Task {
                    await self?.emitNotification(method: "stderr", params: ["message": text])
                }
            }
        }
    }

    func stop() async {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        self.process = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: AppServerError.notConnected)
        }
        pendingRequests.removeAll()
    }

    func request(method: String, params: [String: Any]? = nil) async throws -> Any {
        guard stdinHandle != nil else {
            throw AppServerError.notConnected
        }

        requestID += 1
        let id = requestID

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params ?? [:]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        try writeLineDelimitedMessage(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    func notify(method: String, params: [String: Any]? = nil) async throws {
        guard stdinHandle != nil else {
            throw AppServerError.notConnected
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params ?? [:]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        try writeLineDelimitedMessage(data)
    }

    private func writeLineDelimitedMessage(_ body: Data) throws {
        guard let stdinHandle else {
            throw AppServerError.notConnected
        }
        stdinHandle.write(body)
        stdinHandle.write(Data([0x0A]))
    }

    private func appendIncomingData(_ data: Data) async {
        incomingBuffer.append(data)

        while true {
            if let expectedBodyLength {
                guard incomingBuffer.count >= expectedBodyLength else {
                    return
                }
                let body = incomingBuffer.prefix(expectedBodyLength)
                incomingBuffer.removeFirst(expectedBodyLength)
                self.expectedBodyLength = nil
                await handleMessageData(Data(body))
                continue
            }

            guard let headerRange = incomingBuffer.range(of: Data("\r\n\r\n".utf8)) else {
                if shouldAttemptLineDelimitedParse() {
                    await parseLineDelimitedMessagesIfNeeded()
                }
                return
            }

            let headerData = incomingBuffer.prefix(upTo: headerRange.lowerBound)
            incomingBuffer.removeSubrange(incomingBuffer.startIndex..<headerRange.upperBound)
            guard let header = String(data: headerData, encoding: .utf8) else {
                continue
            }

            let parsedLength = parseContentLength(from: header)
            if let parsedLength {
                expectedBodyLength = parsedLength
                continue
            }

            await parseLineDelimitedMessagesIfNeeded()
            return
        }
    }

    private func parseContentLength(from header: String) -> Int? {
        let lower = header.lowercased()
        guard let range = lower.range(of: "content-length:") else {
            return nil
        }
        let tail = lower[range.upperBound...]
        let digits = tail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return Int(digits)
    }

    private func shouldAttemptLineDelimitedParse() -> Bool {
        for byte in incomingBuffer {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                continue
            }
            return byte == 0x7B
        }
        return false
    }

    private func parseLineDelimitedMessagesIfNeeded() async {
        while let newlineIndex = incomingBuffer.firstIndex(of: 0x0A) {
            let lineData = incomingBuffer.prefix(upTo: newlineIndex)
            incomingBuffer.removeSubrange(incomingBuffer.startIndex...newlineIndex)

            guard !lineData.isEmpty else {
                continue
            }

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                line.hasPrefix("{"),
                let payload = line.data(using: .utf8)
            else {
                continue
            }

            await handleMessageData(payload)
        }
    }

    private func handleMessageData(_ data: Data) async {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let idAny = raw["id"] {
            let id: Int?
            if let intID = idAny as? Int {
                id = intID
            } else if let strID = idAny as? String {
                id = Int(strID)
            } else {
                id = nil
            }

            if let id, let continuation = pendingRequests.removeValue(forKey: id) {
                if let errorObject = raw["error"] as? [String: Any] {
                    let code = (errorObject["code"] as? Int) ?? -1
                    let message = (errorObject["message"] as? String) ?? "Unknown error"
                    continuation.resume(throwing: AppServerError.rpc(code: code, message: message))
                    return
                }

                if let result = raw["result"] {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppServerError.missingResult)
                }
                return
            }
        }

        if let method = raw["method"] as? String {
            let params = raw["params"] as? [String: Any]
            emitNotification(method: method, params: params)
        }
    }

    private func handleProcessTermination(status: Int32) async {
        guard process != nil else {
            return
        }
        await stop()
        onDisconnect?("process exited with status \(status)")
    }

    private func emitNotification(method: String, params: [String: Any]?) {
        onNotification?(method, params)
    }
}
