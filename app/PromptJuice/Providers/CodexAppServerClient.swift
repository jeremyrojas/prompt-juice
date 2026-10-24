import Foundation
import Darwin

protocol CodexRateLimitReading: Sendable {
    func readRateLimits() throws -> CodexRateLimitReadResult
}

struct CodexAppServerClient: CodexRateLimitReading {
    let executableURL: URL?
    let timeout: TimeInterval
    let environment: [String: String]

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 3,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.environment = environment
    }

    func readRateLimits() throws -> CodexRateLimitReadResult {
        guard let executableURL else {
            throw CodexAppServerClientError.executableUnavailable
        }

        try Task.checkCancellation()
        let process = Process()
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.environment = Self.childEnvironment(
            executableURL: executableURL,
            baseEnvironment: environment
        )

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let state = CodexAppServerReadState()

        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            for line in state.appendStdout(data) {
                handleStdoutLine(
                    line,
                    input: stdin.fileHandleForWriting,
                    state: state
                )
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            state.appendStderr(data)
        }

        do {
            try process.run()
            try sendInitialize(to: stdin.fileHandleForWriting)
        } catch {
            cleanup(process: process, exited: exited, stdin: stdin, stdout: stdout, stderr: stderr)
            throw CodexAppServerClientError.launchFailed(error.localizedDescription)
        }

        let deadline = DispatchTime.now() + max(0, timeout)
        var waitResult: DispatchTimeoutResult = .timedOut
        while DispatchTime.now() < deadline, !Task.isCancelled {
            waitResult = state.finished.wait(timeout: min(deadline, .now() + .milliseconds(25)))
            if waitResult == .success { break }
        }
        let result = state.result
        let stderrText = state.stderrText
        cleanup(process: process, exited: exited, stdin: stdin, stdout: stdout, stderr: stderr)

        try Task.checkCancellation()
        if waitResult == .timedOut {
            throw CodexAppServerClientError.timeout(stderrText)
        }

        switch result {
        case .success(let readResult):
            return readResult
        case .failure(let error):
            throw error
        case nil:
            throw CodexAppServerClientError.emptyResponse(stderrText)
        }
    }

    static func childEnvironment(
        executableURL: URL,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        var childEnvironment = baseEnvironment
        let executableDirectory = executableURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        let inheritedPath = baseEnvironment["PATH"].flatMap { path in
            path.isEmpty ? nil : path
        } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathEntries = [executableDirectory]

        for entry in inheritedPath.split(separator: ":", omittingEmptySubsequences: true) {
            let path = String(entry)
            if !pathEntries.contains(path) {
                pathEntries.append(path)
            }
        }

        childEnvironment["PATH"] = pathEntries.joined(separator: ":")
        return childEnvironment
    }

    private func sendInitialize(to input: FileHandle) throws {
        try send(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "prompt_juice",
                        "title": "PromptJuice",
                        "version": "0.1.0"
                    ],
                    "capabilities": [
                        "experimentalApi": true
                    ]
                ]
            ],
            to: input
        )
    }
}

private func handleStdoutLine(
    _ line: String,
    input: FileHandle,
    state: CodexAppServerReadState
) {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any],
          let id = dictionary["id"] as? Int else {
        return
    }

    if id == 1 {
        if let error = dictionary["error"] {
            state.complete(
                .failure(
                    CodexAppServerClientError.initializationFailed("\(error)")
                )
            )
            return
        }

        guard state.markReadRequestSent() else {
            return
        }

        do {
            try send(["method": "initialized", "params": [:]], to: input)
            try send(
                ["method": "account/rateLimits/read", "id": 2, "params": [:]],
                to: input
            )
        } catch {
            state.complete(
                .failure(
                    CodexAppServerClientError.writeFailed(error.localizedDescription)
                )
            )
        }
        return
    }

    if id == 2 {
        do {
            let response = try JSONDecoder().decode(
                CodexAppServerRateLimitResponse.self,
                from: data
            )

            if let error = response.error {
                state.complete(.failure(CodexAppServerClientError.serverError(error.message)))
                return
            }

            guard let result = response.result else {
                state.complete(.failure(CodexAppServerClientError.malformedResponse))
                return
            }

            state.complete(.success(result))
        } catch {
            state.complete(.failure(error))
        }
    }
}

private func send(_ message: [String: Any], to input: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: message)
    try input.write(contentsOf: data + Data([0x0A]))
}

private func cleanup(
    process: Process,
    exited: DispatchSemaphore,
    stdin: Pipe,
    stdout: Pipe,
    stderr: Pipe
) {
    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    try? stdin.fileHandleForWriting.close()

    if process.isRunning {
        process.terminate()
        if exited.wait(timeout: .now() + .milliseconds(200)) == .timedOut,
           process.isRunning {
            // Signal only this Process child; never enumerate or kill other CLI instances.
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + .milliseconds(500))
        }
    }
    try? stdout.fileHandleForReading.close()
    try? stderr.fileHandleForReading.close()
}

private struct CodexAppServerRateLimitResponse: Decodable {
    let id: Int
    let result: CodexRateLimitReadResult?
    let error: CodexAppServerRPCError?
}

private struct CodexAppServerRPCError: Decodable {
    let code: Int?
    let message: String
}

private final class CodexAppServerReadState: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stdoutBytes = 0
    private var stderrBytes = 0
    private static let stdoutLimit = 1_048_576
    private static let stderrLimit = 65_536
    private var stderrBuffer = ""
    private var didSendReadRequest = false
    private var storedResult: Result<CodexRateLimitReadResult, Error>?

    var result: Result<CodexRateLimitReadResult, Error>? {
        lock.withLock {
            storedResult
        }
    }

    var stderrText: String {
        lock.withLock {
            stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func appendStdout(_ data: Data) -> [String] {
        lock.withLock {
            guard storedResult == nil else { return [] }
            guard data.count <= Self.stdoutLimit - stdoutBytes else {
                failOutputLimit()
                return []
            }
            stdoutBytes += data.count
            stdoutBuffer.append(data)
            var lines: [String] = []
            while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = String(decoding: stdoutBuffer[..<newlineIndex], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutBuffer.removeSubrange(...newlineIndex)
                if !line.isEmpty { lines.append(line) }
            }

            return lines
        }
    }

    func appendStderr(_ data: Data) {
        lock.withLock {
            guard storedResult == nil else { return }
            guard data.count <= Self.stderrLimit - stderrBytes else {
                failOutputLimit()
                return
            }
            stderrBytes += data.count
            stderrBuffer += String(decoding: data, as: UTF8.self)
        }
    }

    // Called only with lock held.
    private func failOutputLimit() {
        storedResult = .failure(CodexAppServerClientError.outputTooLarge)
        finished.signal()
    }

    func markReadRequestSent() -> Bool {
        lock.withLock {
            if didSendReadRequest {
                return false
            }

            didSendReadRequest = true
            return true
        }
    }

    func complete(_ result: Result<CodexRateLimitReadResult, Error>) {
        let shouldSignal = lock.withLock {
            guard storedResult == nil else {
                return false
            }

            storedResult = result
            return true
        }

        if shouldSignal {
            finished.signal()
        }
    }
}

enum CodexAppServerClientError: Error, LocalizedError, Equatable {
    case executableUnavailable
    case launchFailed(String)
    case initializationFailed(String)
    case writeFailed(String)
    case serverError(String)
    case outputTooLarge
    case malformedResponse
    case timeout(String)
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "Codex executable unavailable"
        case .launchFailed(let message):
            return "Codex app-server launch failed: \(message)"
        case .initializationFailed(let message):
            return "Codex app-server initialization failed: \(message)"
        case .writeFailed(let message):
            return "Codex app-server write failed: \(message)"
        case .serverError(let message):
            return "Codex app-server returned an error: \(message)"
        case .outputTooLarge:
            return "Codex app-server output exceeded the safety limit"
        case .malformedResponse:
            return "Codex app-server returned an unreadable rate-limit response"
        case .timeout(let stderr):
            return "Codex app-server timed out\(detailSuffix(stderr))"
        case .emptyResponse(let stderr):
            return "Codex app-server returned no rate-limit response\(detailSuffix(stderr))"
        }
    }

    private func detailSuffix(_ detail: String) -> String {
        detail.isEmpty ? "" : ": \(detail)"
    }
}

struct CodexExecutableLocator {
    static let knownExecutablePaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment["PROMPTJUICE_CODEX_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for path in knownExecutablePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        guard let path = which("codex", fileManager: fileManager),
              fileManager.isExecutableFile(atPath: path) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private static func which(
        _ executable: String,
        fileManager: FileManager
    ) -> String? {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let path, !path.isEmpty else {
            return nil
        }

        return path
    }
}

private extension NSLock {
    func withLock<Value>(_ body: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return body()
    }
}
