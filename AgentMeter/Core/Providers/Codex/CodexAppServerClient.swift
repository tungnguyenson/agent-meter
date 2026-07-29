import Foundation

struct JSONRPCError: Error, Codable, Equatable, LocalizedError {
    let code: Int
    let message: String

    var errorDescription: String? {
        "Codex app-server error \(code): \(message)"
    }
}

enum CodexJSONRPCResponseError: Error, Equatable {
    case remoteError(code: Int, message: String)
    case unexpectedResponseID(expected: Int, actual: Int)
    case malformedMessage
    case missingResult
}

enum CodexJSONRPCResponseDecoder {
    private struct Envelope<Result: Decodable>: Decodable {
        let id: Int
        let result: Result?
        let error: JSONRPCError?
    }

    static func decode<Result: Decodable>(
        line: String,
        expectedID: Int,
        as type: Result.Type
    ) throws -> Result {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope<Result>.self, from: data) else {
            throw CodexJSONRPCResponseError.malformedMessage
        }
        guard envelope.id == expectedID else {
            throw CodexJSONRPCResponseError.unexpectedResponseID(
                expected: expectedID,
                actual: envelope.id
            )
        }
        if let error = envelope.error {
            throw CodexJSONRPCResponseError.remoteError(
                code: error.code,
                message: error.message
            )
        }
        guard let result = envelope.result else {
            throw CodexJSONRPCResponseError.missingResult
        }
        return result
    }
}

enum JSONRPCResponseDecoder {
    private struct Envelope<Result: Decodable>: Decodable {
        let result: Result?
        let error: JSONRPCError?
    }

    static func decode<Result: Decodable>(_ type: Result.Type, from data: Data) throws -> Result {
        let envelope = try JSONDecoder().decode(Envelope<Result>.self, from: data)
        if let error = envelope.error { throw error }
        guard let result = envelope.result else {
            throw CodexAppServerError.missingResult
        }
        return result
    }
}

enum CodexAppServerError: Error, LocalizedError {
    case binaryNotFound
    case unsupportedVersion(String)
    case processUnavailable
    case invalidMessage
    case missingResult
    case requestTimedOut
    case processExited
    case authenticationRequired
    case restartBackoff(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Codex CLI was not found. Install Codex or set its path in Settings."
        case .unsupportedVersion(let version):
            return "Codex CLI \(version) is unsupported. Version 0.146.0 or newer is required."
        case .processUnavailable:
            return "Codex app-server could not be started."
        case .invalidMessage:
            return "Codex app-server returned an invalid message."
        case .missingResult:
            return "Codex app-server returned neither a result nor an error."
        case .requestTimedOut:
            return "Codex app-server request timed out."
        case .processExited:
            return "Codex app-server exited unexpectedly."
        case .authenticationRequired:
            return "Codex must be signed in with a supported ChatGPT account."
        case .restartBackoff(let seconds):
            return "Codex app-server restart is paused for \(Int(seconds)) seconds."
        }
    }
}

protocol CodexAppServerServing: Sendable {
    func readAccount() async throws -> CodexAccountResponse
    func readRateLimits() async throws -> CodexRateLimitsResponse
    func readTokenUsage() async throws -> CodexTokenUsageResponse
    func stop() async
}

actor CodexAppServerClient: CodexAppServerServing {
    private static let maximumMessageBytes = 1_048_576
    private let binaryURL: URL
    private let requestTimeout: TimeInterval
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var pendingOutputChunks: [Int: Data] = [:]
    private var nextExpectedOutputSequence = 0
    private let outputReadQueue = DispatchQueue(
        label: "com.agentmeter.codex-output-reader"
    )
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var isInitialized = false
    private var isInitializing = false
    private var initializationWaiters: [CheckedContinuation<Void, Error>] = []
    private var processGeneration = 0
    private var restartFailureCount = 0
    private var nextLaunchAt: Date?

    init(binaryURL: URL, requestTimeout: TimeInterval = 15) {
        self.binaryURL = binaryURL
        self.requestTimeout = requestTimeout
    }

    func readAccount() async throws -> CodexAccountResponse {
        try await request(
            method: "account/read",
            params: ["refreshToken": false],
            responseType: CodexAccountResponse.self
        )
    }

    func readRateLimits() async throws -> CodexRateLimitsResponse {
        try await request(
            method: "account/rateLimits/read",
            params: [:],
            responseType: CodexRateLimitsResponse.self
        )
    }

    func readTokenUsage() async throws -> CodexTokenUsageResponse {
        try await request(
            method: "account/usage/read",
            params: [:],
            responseType: CodexTokenUsageResponse.self
        )
    }

    func stop() {
        stopProcess(preserveBackoff: false)
    }

    private func stopProcess(preserveBackoff: Bool) {
        processGeneration += 1
        outputHandle?.readabilityHandler = nil
        outputHandle?.closeFile()
        outputHandle = nil
        errorHandle?.readabilityHandler = nil
        errorHandle?.closeFile()
        errorHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingOutputChunks.removeAll()
        nextExpectedOutputSequence = 0
        inputHandle?.closeFile()
        inputHandle = nil
        let processToStop = process
        process = nil
        if let processToStop {
            Self.terminate(processToStop)
        }
        if !preserveBackoff {
            restartFailureCount = 0
            nextLaunchAt = nil
        }
        isInitialized = false
        isInitializing = false
        failPending(with: CodexAppServerError.processExited)
        finishInitializationWaiters(with: .failure(CodexAppServerError.processExited))
    }

    private func request<Result: Decodable>(
        method: String,
        params: [String: Any],
        responseType: Result.Type
    ) async throws -> Result {
        try await ensureStarted()
        let data = try await sendRequest(method: method, params: params)
        let result = try JSONRPCResponseDecoder.decode(responseType, from: data)
        restartFailureCount = 0
        nextLaunchAt = nil
        return result
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true, isInitialized {
            return
        }
        if isInitializing {
            try await withCheckedThrowingContinuation { continuation in
                initializationWaiters.append(continuation)
            }
            return
        }

        isInitializing = true
        do {
            if let nextLaunchAt, nextLaunchAt > Date() {
                throw CodexAppServerError.restartBackoff(
                    nextLaunchAt.timeIntervalSinceNow
                )
            }
            try launchProcess()
            let data = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "agent_meter",
                        "title": "Agent Meter",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                    ]
                ]
            )
            _ = try JSONRPCResponseDecoder.decode(InitializeResponse.self, from: data)
            try sendNotification(method: "initialized", params: [:])
            isInitialized = true
            isInitializing = false
            finishInitializationWaiters(with: .success(()))
        } catch {
            isInitialized = false
            isInitializing = false
            finishInitializationWaiters(with: .failure(error))
            stopProcess(preserveBackoff: true)
            throw error
        }
    }

    private func launchProcess() throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["app-server"]
        process.environment = CodexProcessEnvironment.environment(for: binaryURL)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            registerUnexpectedExit()
            throw CodexAppServerError.processUnavailable
        }

        processGeneration += 1
        let generation = processGeneration
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        errorHandle = errorPipe.fileHandleForReading
        drainErrors(from: errorPipe.fileHandleForReading)
        startReading(from: outputPipe.fileHandleForReading, generation: generation)
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessExit(generation: generation) }
        }
    }

    private func startReading(from handle: FileHandle, generation: Int) {
        var sequence = 0
        outputHandle = handle
        handle.readabilityHandler = { [weak self] readableHandle in
            let chunk = readableHandle.availableData
            guard !chunk.isEmpty else {
                readableHandle.readabilityHandler = nil
                return
            }
            self?.outputReadQueue.async { [weak self] in
                let currentSequence = sequence
                sequence += 1
                Task {
                    await self?.receive(
                        chunk: chunk,
                        sequence: currentSequence,
                        generation: generation
                    )
                }
            }
        }
    }

    private func receive(chunk: Data, sequence: Int, generation: Int) {
        guard generation == processGeneration else { return }
        pendingOutputChunks[sequence] = chunk
        while let nextChunk = pendingOutputChunks.removeValue(
            forKey: nextExpectedOutputSequence
        ) {
            nextExpectedOutputSequence += 1
            consumeOrderedOutput(nextChunk, generation: generation)
        }
    }

    private func consumeOrderedOutput(_ chunk: Data, generation: Int) {
        outputBuffer.append(chunk)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = outputBuffer[..<newline]
            outputBuffer.removeSubrange(outputBuffer.startIndex...newline)
            guard lineData.count <= Self.maximumMessageBytes,
                  let line = String(data: lineData, encoding: .utf8) else {
                rejectProcessOutput(generation: generation)
                return
            }
            receive(line: line)
        }
        guard outputBuffer.count <= Self.maximumMessageBytes else {
            rejectProcessOutput(generation: generation)
            return
        }
    }

    private nonisolated func drainErrors(from handle: FileHandle) {
        handle.readabilityHandler = { readableHandle in
            guard !readableHandle.availableData.isEmpty else {
                readableHandle.readabilityHandler = nil
                return
            }
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> Data {
        let id = nextRequestID
        nextRequestID += 1
        let message: [String: Any] = ["method": method, "id": id, "params": params]

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do {
                    try write(message)
                    scheduleTimeout(for: id)
                } catch {
                    pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id: id) }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try write(["method": method, "params": params])
    }

    private func write(_ message: [String: Any]) throws {
        guard let inputHandle else { throw CodexAppServerError.processUnavailable }
        let data = try JSONSerialization.data(withJSONObject: message)
        do {
            try inputHandle.write(contentsOf: data + Data([0x0A]))
        } catch {
            throw CodexAppServerError.processExited
        }
    }

    private func receive(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let id = object["id"] as? Int else {
            handleNotification(method: object["method"] as? String)
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: data)
    }

    private func handleNotification(method: String?) {
        guard method == "account/rateLimits/updated"
                || method == "account/updated" else {
            return
        }
        NotificationCenter.default.post(name: .codexUsageDidChange, object: nil)
    }

    private func scheduleTimeout(for id: Int) {
        let timeout = requestTimeout
        timeoutTasks[id] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            await self?.timeoutRequest(id: id)
        }
    }

    private func timeoutRequest(id: Int) {
        guard pending[id] != nil else { return }
        rejectProcessOutput(
            generation: processGeneration,
            error: CodexAppServerError.requestTimedOut
        )
    }

    private func cancelRequest(id: Int) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func handleProcessExit(generation: Int) {
        guard generation == processGeneration else { return }
        process = nil
        inputHandle = nil
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        errorHandle?.readabilityHandler = nil
        errorHandle?.closeFile()
        errorHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingOutputChunks.removeAll()
        nextExpectedOutputSequence = 0
        isInitialized = false
        isInitializing = false
        registerUnexpectedExit()
        failPending(with: CodexAppServerError.processExited)
        finishInitializationWaiters(with: .failure(CodexAppServerError.processExited))
    }

    private func rejectProcessOutput(generation: Int) {
        rejectProcessOutput(
            generation: generation,
            error: CodexAppServerError.invalidMessage
        )
    }

    private func rejectProcessOutput(generation: Int, error: Error) {
        guard generation == processGeneration else { return }
        processGeneration += 1
        outputHandle?.readabilityHandler = nil
        outputHandle?.closeFile()
        outputHandle = nil
        errorHandle?.readabilityHandler = nil
        errorHandle?.closeFile()
        errorHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingOutputChunks.removeAll()
        nextExpectedOutputSequence = 0
        inputHandle?.closeFile()
        inputHandle = nil
        let failedProcess = process
        process = nil
        isInitialized = false
        isInitializing = false
        failPending(with: error)
        finishInitializationWaiters(with: .failure(error))
        registerUnexpectedExit()
        if let failedProcess {
            Self.terminate(failedProcess)
        }
    }

    private nonisolated static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func finishInitializationWaiters(with result: Result<Void, Error>) {
        let waiters = initializationWaiters
        initializationWaiters.removeAll()
        waiters.forEach { $0.resume(with: result) }
    }

    private func registerUnexpectedExit() {
        restartFailureCount += 1
        let delay = min(pow(2, Double(restartFailureCount - 1)), 60)
        nextLaunchAt = Date().addingTimeInterval(delay)
    }
}

private struct InitializeResponse: Decodable {
    let userAgent: String?
}

extension Notification.Name {
    static let codexUsageDidChange = Notification.Name(
        "com.agentmeter.codex-usage-did-change"
    )
}
