import Darwin
import Foundation

struct ClaudeCLICommandResult: Sendable, Equatable {
    let standardOutput: Data
    let terminationStatus: Int32
}

protocol ClaudeCLICommandRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> ClaudeCLICommandResult
}

enum ClaudeCLICommandError: Error, Sendable, Equatable {
    case launchFailed
    case timedOut
    case outputTooLarge
}

struct ClaudeCLICommandRunner: ClaudeCLICommandRunning {
    let maximumOutputBytes: Int

    init(maximumOutputBytes: Int = 64 * 1_024) {
        self.maximumOutputBytes = maximumOutputBytes
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> ClaudeCLICommandResult {
        let process = Process()
        let output = Pipe()
        let state = ClaudeBoundedOutputState(maximumBytes: maximumOutputBytes)
        let finished = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            finished.signal()
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                state.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw ClaudeCLICommandError.launchFailed
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            terminate(process)
            output.fileHandleForReading.readabilityHandler = nil
            throw ClaudeCLICommandError.timedOut
        }

        output.fileHandleForReading.readabilityHandler = nil
        state.append(output.fileHandleForReading.readDataToEndOfFile())

        guard !state.didOverflow else {
            throw ClaudeCLICommandError.outputTooLarge
        }

        return ClaudeCLICommandResult(
            standardOutput: state.data,
            terminationStatus: process.terminationStatus
        )
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(0.25)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}

private final class ClaudeBoundedOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var storedData = Data()
    private var overflow = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var data: Data {
        lock.withClaudeProbeLock { storedData }
    }

    var didOverflow: Bool {
        lock.withClaudeProbeLock { overflow }
    }

    func append(_ data: Data) {
        lock.withClaudeProbeLock {
            guard !data.isEmpty else {
                return
            }

            let remaining = max(0, maximumBytes - storedData.count)
            if data.count > remaining {
                storedData.append(data.prefix(remaining))
                overflow = true
            } else {
                storedData.append(data)
            }
        }
    }
}

struct ClaudeAuthConfigurationReader {
    private static let maximumSettingsBytes = 1 * 1_024 * 1_024

    let fileManager: FileManager
    let homeDirectory: URL
    let managedSettingsDirectory: URL
    let managedPreferenceDocuments: [Data]?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        managedSettingsDirectory: URL = URL(
            fileURLWithPath: "/Library/Application Support/ClaudeCode",
            isDirectory: true
        ),
        managedPreferenceDocuments: [Data]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.managedSettingsDirectory = managedSettingsDirectory
        self.managedPreferenceDocuments = managedPreferenceDocuments
    }

    func evidence(
        environment: [String: String],
        additionalSettingsDocuments: [Data] = []
    ) -> ClaudeBillingEvidence {
        var documents = additionalSettingsDocuments
        var readFailed = false

        let configDirectory = resolvedConfigDirectory(environment: environment)
        if let configDirectory {
            read(
                configDirectory.appendingPathComponent("settings.json", isDirectory: false),
                documents: &documents,
                readFailed: &readFailed
            )
        } else {
            readFailed = true
        }

        read(
            managedSettingsDirectory.appendingPathComponent(
                "managed-settings.json",
                isDirectory: false
            ),
            documents: &documents,
            readFailed: &readFailed
        )

        let dropInDirectory = managedSettingsDirectory.appendingPathComponent(
            "managed-settings.d",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: dropInDirectory.path) {
            do {
                let dropIns = try fileManager.contentsOfDirectory(
                    at: dropInDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for url in dropIns {
                    read(url, documents: &documents, readFailed: &readFailed)
                }
            } catch {
                readFailed = true
            }
        }

        if let managedPreferenceDocuments {
            documents.append(contentsOf: managedPreferenceDocuments)
        } else {
            switch Self.managedPreferenceSettings() {
            case .absent:
                break
            case .document(let data):
                documents.append(data)
            case .failed:
                readFailed = true
            }
        }

        return ClaudeBillingEvidenceScanner.scan(
            environment: environment,
            settingsDocuments: documents,
            settingsReadFailed: readFailed
        )
    }

    private func resolvedConfigDirectory(environment: [String: String]) -> URL? {
        guard let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty else {
            return homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        }

        if configured == "~" {
            return homeDirectory
        }
        if configured.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(configured.dropFirst(2)), isDirectory: true)
        }
        guard configured.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
    }

    private func read(
        _ url: URL,
        documents: inout [Data],
        readFailed: inout Bool
    ) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size <= Self.maximumSettingsBytes else {
                readFailed = true
                return
            }
            documents.append(try Data(contentsOf: url))
        } catch {
            readFailed = true
        }
    }

    private static func managedPreferenceSettings() -> ManagedPreferenceSettings {
        guard let defaults = UserDefaults(suiteName: "com.anthropic.claudecode") else {
            return .absent
        }

        for key in ["Settings", "settings"] {
            guard let value = defaults.object(forKey: key) else {
                continue
            }

            if let data = value as? Data {
                return .document(data)
            }
            if let string = value as? String,
               let data = string.data(using: .utf8) {
                return .document(data)
            }
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value) {
                return .document(data)
            }
            return .failed
        }

        return .absent
    }

    private enum ManagedPreferenceSettings {
        case absent
        case document(Data)
        case failed
    }
}

struct ClaudeVersionProbe {
    let runner: any ClaudeCLICommandRunning
    let timeout: TimeInterval

    init(
        runner: any ClaudeCLICommandRunning = ClaudeCLICommandRunner(),
        timeout: TimeInterval = 3
    ) {
        self.runner = runner
        self.timeout = timeout
    }

    func probe(
        executableURL: URL,
        environment: [String: String]
    ) -> ClaudeVersionGateResult {
        guard let result = try? runner.run(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment,
            timeout: timeout
        ), result.terminationStatus == 0 else {
            return .unreadable
        }

        return ClaudeVersionGateResult.evaluate(result.standardOutput)
    }
}

struct ClaudeAuthProbe {
    let runner: any ClaudeCLICommandRunning
    let configurationReader: ClaudeAuthConfigurationReader
    let timeout: TimeInterval

    init(
        runner: any ClaudeCLICommandRunning = ClaudeCLICommandRunner(),
        configurationReader: ClaudeAuthConfigurationReader = ClaudeAuthConfigurationReader(),
        timeout: TimeInterval = 3
    ) {
        self.runner = runner
        self.configurationReader = configurationReader
        self.timeout = timeout
    }

    func probe(
        executableURL: URL,
        environment: [String: String],
        additionalSettingsDocuments: [Data] = []
    ) -> ClaudeAuthentication {
        let evidence = configurationReader.evidence(
            environment: environment,
            additionalSettingsDocuments: additionalSettingsDocuments
        )

        guard let result = try? runner.run(
            executableURL: executableURL,
            arguments: ["auth", "status"],
            environment: environment,
            timeout: timeout
        ), result.terminationStatus == 0 || result.terminationStatus == 1 else {
            return .checkFailed
        }

        let classification = ClaudeAuthClassifier.classify(
            authStatusData: result.standardOutput,
            evidence: evidence
        )

        switch (result.terminationStatus, classification) {
        case (0, .signedOut), (1, .subscription), (1, .apiBilling), (1, .externalProvider):
            return .unsupported
        default:
            return classification
        }
    }
}

private extension NSLock {
    func withClaudeProbeLock<Value>(_ body: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return body()
    }
}
