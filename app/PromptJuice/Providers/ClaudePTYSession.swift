import Darwin
import Foundation

enum ClaudeUsageProbeIneligibility: Sendable, Equatable {
    case unsupportedVersion
    case authentication
}

enum ClaudeUsageTransportOutcome: Sendable, Equatable {
    case captured(Data)
    case workspaceTrustRequired
    case ineligible(ClaudeUsageProbeIneligibility)
    case startupOnly
    case timedOut
    case cancelled
    case outputTooLarge
    case launchFailed
    case processFailed
}

protocol ClaudeUsageTransporting: Sendable {
    func captureUsage(
        executableURL: URL,
        version: ClaudeVersionGateResult,
        authentication: ClaudeAuthentication,
        workspaceURL: URL,
        environment: [String: String],
        isCancelled: @escaping @Sendable () -> Bool
    ) -> ClaudeUsageTransportOutcome
}

enum ClaudeProbeWorkspaceError: Error, Sendable, Equatable {
    case unsafeDirectory
    case creationFailed
}

struct ClaudeProbeWorkspace: @unchecked Sendable {
    let url: URL
    let fileManager: FileManager

    init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PromptJuice/ClaudeProbe/Workspace"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
    }

    func prepare() throws -> URL {
        let probeDirectory = url.deletingLastPathComponent()
        try prepareOwnerOnlyDirectory(probeDirectory)
        try prepareOwnerOnlyDirectory(url)
        return url
    }

    private func prepareOwnerOnlyDirectory(_ directory: URL) throws {
        var information = stat()
        let result = directory.path.withCString { lstat($0, &information) }
        if result == 0 {
            guard (information.st_mode & S_IFMT) == S_IFDIR,
                  information.st_uid == getuid() else {
                throw ClaudeProbeWorkspaceError.unsafeDirectory
            }
        } else {
            guard errno == ENOENT else {
                throw ClaudeProbeWorkspaceError.creationFailed
            }
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw ClaudeProbeWorkspaceError.creationFailed
            }
        }

        guard chmod(directory.path, 0o700) == 0 else {
            throw ClaudeProbeWorkspaceError.creationFailed
        }
    }
}

struct ClaudePTYConfiguration: Sendable, Equatable {
    let startupTimeout: TimeInterval
    let commandTimeout: TimeInterval
    let settleInterval: TimeInterval
    let terminationGrace: TimeInterval
    let pollInterval: TimeInterval
    let maximumOutputBytes: Int

    static let production = ClaudePTYConfiguration(
        startupTimeout: 8,
        commandTimeout: 12,
        settleInterval: 0.75,
        terminationGrace: 0.25,
        pollInterval: 0.01,
        maximumOutputBytes: ClaudeUsageParser.maximumOutputBytes
    )
}

struct ClaudePTYSession: ClaudeUsageTransporting {
    static let fixedArguments = [
        "--safe-mode",
        "--ax-screen-reader",
        "--allowed-tools",
        "",
    ]
    static let usageCommand = Data("/usage\r".utf8)
    static let cursorPositionResponse = Data("\u{001B}[1;1R".utf8)

    let configuration: ClaudePTYConfiguration

    init(configuration: ClaudePTYConfiguration = .production) {
        self.configuration = configuration
    }

    func captureUsage(
        executableURL: URL,
        version: ClaudeVersionGateResult,
        authentication: ClaudeAuthentication,
        workspaceURL: URL,
        environment: [String: String],
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> ClaudeUsageTransportOutcome {
        guard case .supported(let installedVersion) = version,
              installedVersion >= .minimumUsageVersion else {
            return .ineligible(.unsupportedVersion)
        }
        guard authentication.permitsUsageProbe else {
            return .ineligible(.authentication)
        }
        guard Self.isOwnerOnlyDirectory(workspaceURL) else {
            return .launchFailed
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        var terminalSize = winsize(ws_row: 60, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &terminalSize) == 0 else {
            return .launchFailed
        }
        defer {
            if master >= 0 {
                close(master)
            }
            if slave >= 0 {
                close(slave)
            }
        }

        let currentFlags = fcntl(master, F_GETFL)
        guard currentFlags >= 0,
              fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            return .launchFailed
        }

        let childEnvironment = Self.childEnvironment(from: environment)
        guard let processIdentifier = Self.spawn(
            executableURL: executableURL,
            arguments: Self.fixedArguments,
            environment: childEnvironment,
            workspaceURL: workspaceURL,
            master: master,
            slave: slave
        ) else {
            return .launchFailed
        }

        close(slave)
        slave = -1

        var output = Data()
        var processWasReaped = false
        var sentUsageCommand = false
        var cursorResponsesSent = 0
        var lastOutputAt = Date()
        var usageCompletedAt: Date?
        var deadline = Date().addingTimeInterval(configuration.startupTimeout)

        while true {
            let readResult = Self.readAvailable(
                from: master,
                into: &output,
                maximumBytes: configuration.maximumOutputBytes
            )
            switch readResult {
            case .overflow:
                Self.terminateProcessGroup(
                    processIdentifier,
                    grace: configuration.terminationGrace,
                    wasReaped: &processWasReaped
                )
                return .outputTooLarge
            case .readData:
                lastOutputAt = Date()
                usageCompletedAt = nil
            case .noData:
                break
            }

            let queryCount = Self.occurrenceCount(
                of: Data("\u{001B}[6n".utf8),
                in: output
            )
            while cursorResponsesSent < queryCount {
                guard Self.writeAll(Self.cursorPositionResponse, to: master) else {
                    Self.terminateProcessGroup(
                        processIdentifier,
                        grace: configuration.terminationGrace,
                        wasReaped: &processWasReaped
                    )
                    return .processFailed
                }
                cursorResponsesSent += 1
            }

            let visibleText = ClaudeUsageParser.visibleTerminalText(from: output)
            if Self.requiresWorkspaceTrust(visibleText) {
                Self.terminateProcessGroup(
                    processIdentifier,
                    grace: configuration.terminationGrace,
                    wasReaped: &processWasReaped
                )
                return .workspaceTrustRequired
            }

            if !sentUsageCommand, Self.isReadyForCommand(visibleText) {
                guard Self.writeAll(Self.usageCommand, to: master) else {
                    Self.terminateProcessGroup(
                        processIdentifier,
                        grace: configuration.terminationGrace,
                        wasReaped: &processWasReaped
                    )
                    return .processFailed
                }
                sentUsageCommand = true
                deadline = Date().addingTimeInterval(configuration.commandTimeout)
            }

            if sentUsageCommand, Self.hasCompleteUsageOutcome(output) {
                usageCompletedAt = usageCompletedAt ?? Date()
                if Date().timeIntervalSince(lastOutputAt) >= configuration.settleInterval,
                   Date().timeIntervalSince(usageCompletedAt ?? Date()) >= configuration.settleInterval {
                    Self.terminateProcessGroup(
                        processIdentifier,
                        grace: configuration.terminationGrace,
                        wasReaped: &processWasReaped
                    )
                    return .captured(output)
                }
            }

            if isCancelled() {
                Self.terminateProcessGroup(
                    processIdentifier,
                    grace: configuration.terminationGrace,
                    wasReaped: &processWasReaped
                )
                return .cancelled
            }

            var status: Int32 = 0
            let waitResult = waitpid(processIdentifier, &status, WNOHANG)
            if waitResult == processIdentifier {
                processWasReaped = true
                if sentUsageCommand, Self.hasCompleteUsageOutcome(output) {
                    return .captured(output)
                }
                return sentUsageCommand ? .startupOnly : .processFailed
            }

            if Date() >= deadline {
                Self.terminateProcessGroup(
                    processIdentifier,
                    grace: configuration.terminationGrace,
                    wasReaped: &processWasReaped
                )
                return sentUsageCommand ? .startupOnly : .timedOut
            }

            Thread.sleep(forTimeInterval: configuration.pollInterval)
        }
    }

    private enum ReadResult {
        case noData
        case readData
        case overflow
    }

    private static func childEnvironment(from environment: [String: String]) -> [String: String] {
        var result = environment
        result["TERM"] = "xterm-256color"
        result["DISABLE_AUTOUPDATER"] = "1"
        result["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        return result
    }

    private static func isOwnerOnlyDirectory(_ url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { lstat($0, &information) }
        return result == 0
            && (information.st_mode & S_IFMT) == S_IFDIR
            && information.st_uid == getuid()
            && (information.st_mode & 0o077) == 0
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workspaceURL: URL,
        master: Int32,
        slave: Int32
    ) -> pid_t? {
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            return nil
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        guard posix_spawn_file_actions_adddup2(&fileActions, slave, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, slave, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, slave, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&fileActions, master) == 0,
              posix_spawn_file_actions_addclose(&fileActions, slave) == 0,
              posix_spawn_file_actions_addchdir_np(&fileActions, workspaceURL.path) == 0 else {
            return nil
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            return nil
        }
        defer { posix_spawnattr_destroy(&attributes) }

        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            return nil
        }

        let argumentStrings = [executableURL.path] + arguments
        let environmentStrings = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        var processIdentifier = pid_t()

        let spawnResult = withCStringArray(argumentStrings) { argumentPointers in
            withCStringArray(environmentStrings) { environmentPointers in
                executableURL.path.withCString { executablePath in
                    posix_spawn(
                        &processIdentifier,
                        executablePath,
                        &fileActions,
                        &attributes,
                        argumentPointers,
                        environmentPointers
                    )
                }
            }
        }
        return spawnResult == 0 ? processIdentifier : nil
    }

    private static func withCStringArray<Result>(
        _ strings: [String],
        body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
    ) -> Result {
        let pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        var terminatedPointers = pointers + [nil]
        return terminatedPointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }

    private static func readAvailable(
        from fileDescriptor: Int32,
        into output: inout Data,
        maximumBytes: Int
    ) -> ReadResult {
        var readAnyData = false
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                readAnyData = true
                if output.count + count > maximumBytes {
                    return .overflow
                }
                output.append(buffer, count: count)
                continue
            }
            if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK || errno == EIO {
                return readAnyData ? .readData : .noData
            }
            return readAnyData ? .readData : .noData
        }
    }

    private static func writeAll(_ data: Data, to fileDescriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return true
            }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if count > 0 {
                    offset += count
                } else if errno != EINTR {
                    return false
                }
            }
            return true
        }
    }

    private static func occurrenceCount(of needle: Data, in haystack: Data) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return 0
        }

        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, in: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func requiresWorkspaceTrust(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("do you trust the files in this folder")
            || normalized.contains("yes, i trust this folder")
            || normalized.contains("is this a project you trust")
            || normalized.contains("trust this workspace")
    }

    private static func isReadyForCommand(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasPrompt = lines.contains("$") || lines.contains(">")
        return hasPrompt
            && (text.contains("Claude Code v")
                || text.contains("Claude Code ready")
                || text.contains("manual mode on"))
    }

    private static func hasCompleteUsageOutcome(_ data: Data) -> Bool {
        let text = ClaudeUsageParser.visibleTerminalText(from: data)
        let panelStart: String.Index?
        if let commandEcho = text.range(of: "you: /usage", options: .caseInsensitive) {
            panelStart = commandEcho.lowerBound
        } else if let settings = text.range(of: "Settings", options: .caseInsensitive) {
            let panelPrefix = text[settings.lowerBound...].prefix(200).lowercased()
            panelStart = panelPrefix.contains("status")
                && panelPrefix.contains("config")
                && panelPrefix.contains("usage")
                && panelPrefix.contains("stats")
                ? settings.lowerBound
                : nil
        } else {
            panelStart = nil
        }

        guard let panelStart else {
            return false
        }
        let result = ClaudeUsageParser().parse(Data(text[panelStart...].utf8))
        return result.reading != nil || result.rateLimitObserved
    }

    private static func terminateProcessGroup(
        _ processIdentifier: pid_t,
        grace: TimeInterval,
        wasReaped: inout Bool
    ) {
        guard !wasReaped else {
            return
        }

        kill(-processIdentifier, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        var status: Int32 = 0
        while Date() < deadline {
            let result = waitpid(processIdentifier, &status, WNOHANG)
            if result == processIdentifier || (result == -1 && errno == ECHILD) {
                wasReaped = true
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        kill(-processIdentifier, SIGKILL)
        while waitpid(processIdentifier, &status, 0) == -1, errno == EINTR {}
        wasReaped = true
    }
}

enum ClaudeUsageProbeOutcome: Sendable, Equatable {
    case parsed(ClaudeUsageParseResult)
    case workspaceTrustRequired
    case ineligible(ClaudeUsageProbeIneligibility)
    case timedOut
    case cancelled
    case outputTooLarge
    case launchFailed
    case processFailed
    case startupOnly
}

struct ClaudeUsageProbe: Sendable {
    let transport: any ClaudeUsageTransporting
    let parser: ClaudeUsageParser

    init(
        transport: any ClaudeUsageTransporting = ClaudePTYSession(),
        parser: ClaudeUsageParser = ClaudeUsageParser()
    ) {
        self.transport = transport
        self.parser = parser
    }

    func probe(
        executableURL: URL,
        version: ClaudeVersionGateResult,
        authentication: ClaudeAuthentication,
        workspaceURL: URL,
        environment: [String: String],
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> ClaudeUsageProbeOutcome {
        for attempt in 0..<2 {
            let outcome = transport.captureUsage(
                executableURL: executableURL,
                version: version,
                authentication: authentication,
                workspaceURL: workspaceURL,
                environment: environment,
                isCancelled: isCancelled
            )
            switch outcome {
            case .captured(let data):
                return .parsed(parser.parse(data, now: now, calendar: calendar))
            case .startupOnly where attempt == 0:
                continue
            case .workspaceTrustRequired:
                return .workspaceTrustRequired
            case .ineligible(let reason):
                return .ineligible(reason)
            case .startupOnly:
                return .startupOnly
            case .timedOut:
                return .timedOut
            case .cancelled:
                return .cancelled
            case .outputTooLarge:
                return .outputTooLarge
            case .launchFailed:
                return .launchFailed
            case .processFailed:
                return .processFailed
            }
        }
        return .startupOnly
    }
}
