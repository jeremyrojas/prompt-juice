import Foundation

protocol CodexRateLimitReading {
    func readRateLimits() throws -> CodexRateLimitReadResult
}

struct CodexAppServerClient: CodexRateLimitReading {
    let executableURL: URL?
    let timeout: TimeInterval

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 3
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func readRateLimits() throws -> CodexRateLimitReadResult {
        guard let executableURL else {
            throw CodexAppServerClientError.executableUnavailable
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server"]

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
            cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr)
            throw CodexAppServerClientError.launchFailed(error.localizedDescription)
        }

        let waitResult = state.finished.wait(timeout: .now() + timeout)
        let result = state.result
        let stderrText = state.stderrText
        cleanup(process: process, stdin: stdin, stdout: stdout, stderr: stderr)

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
    input.write(data)
    input.write(Data([0x0A]))
}

private func cleanup(
    process: Process,
    stdin: Pipe,
    stdout: Pipe,
    stderr: Pipe
) {
    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    try? stdin.fileHandleForWriting.close()

    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
    }
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
    private var stdoutBuffer = ""
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
            guard let text = String(data: data, encoding: .utf8) else {
                return []
            }

            stdoutBuffer += text
            var lines: [String] = []

            while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
                let line = String(stdoutBuffer[..<newlineIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutBuffer.removeSubrange(...newlineIndex)

                if !line.isEmpty {
                    lines.append(line)
                }
            }

            return lines
        }
    }

    func appendStderr(_ data: Data) {
        lock.withLock {
            if let text = String(data: data, encoding: .utf8) {
                stderrBuffer += text
            }
        }
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
    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment["PROMPTJUICE_CODEX_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for path in [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ] where fileManager.isExecutableFile(atPath: path) {
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
