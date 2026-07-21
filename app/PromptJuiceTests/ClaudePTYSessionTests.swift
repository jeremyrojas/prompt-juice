import Darwin
import Foundation
import XCTest
@testable import PromptJuice

final class ClaudePTYSessionTests: XCTestCase {
    func testWorkspaceIsStableOwnerOnlyAndRejectsSymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspaceURL = root.appendingPathComponent("ClaudeProbe/Workspace", isDirectory: true)
        let prepared = try ClaudeProbeWorkspace(url: workspaceURL).prepare()
        XCTAssertEqual(prepared, workspaceURL)
        XCTAssertEqual(permissions(of: prepared) & 0o777, 0o700)
        XCTAssertEqual(try ClaudeProbeWorkspace(url: workspaceURL).prepare(), workspaceURL)

        let target = root.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("ClaudeProbe/LinkedWorkspace", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ClaudeProbeWorkspace(url: link).prepare()) { error in
            XCTAssertEqual(error as? ClaudeProbeWorkspaceError, .unsafeDirectory)
        }
    }

    func testFixedArgumentsUsageCommandAndCursorResponseAreExact() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let argumentsURL = fixture.root.appendingPathComponent("arguments")
        let inputURL = fixture.root.appendingPathComponent("input")
        let cursorURL = fixture.root.appendingPathComponent("cursor")
        let script = try makeScript(
            in: fixture.root,
            body: """
            printf '%s\\n' "$@" > "$PROMPTJUICE_TEST_ARGUMENTS"
            stty raw -echo
            printf '\\033[6n'
            dd bs=1 count=6 of="$PROMPTJUICE_TEST_CURSOR" 2>/dev/null
            printf 'Claude Code ready\\r\\n$\\r\\n'
            dd bs=1 count=7 of="$PROMPTJUICE_TEST_INPUT" 2>/dev/null
            printf '\\r\\nyou: /usage\\r\\nUsage\\r\\nCurrent session\\r\\n42%% used\\r\\nResets at 3:14 PM\\r\\n'
            sleep 10
            """
        )

        let outcome = session().captureUsage(
            executableURL: script,
            version: .supported(.minimumUsageVersion),
            authentication: .subscription(plan: "max"),
            workspaceURL: fixture.workspace,
            environment: testEnvironment([
                "PROMPTJUICE_TEST_ARGUMENTS": argumentsURL.path,
                "PROMPTJUICE_TEST_INPUT": inputURL.path,
                "PROMPTJUICE_TEST_CURSOR": cursorURL.path,
            ])
        )

        guard case .captured = outcome else {
            return XCTFail("Expected captured output, received \(outcome)")
        }
        let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
            .components(separatedBy: "\n")
            .dropLast()
        XCTAssertEqual(Array(arguments), ClaudePTYSession.fixedArguments)
        XCTAssertEqual(try Data(contentsOf: inputURL), ClaudePTYSession.usageCommand)
        XCTAssertEqual(
            try Data(contentsOf: cursorURL),
            ClaudePTYSession.cursorPositionResponse
        )
    }

    func testWorkspaceTrustIsTypedAndStopsBeforeUsageInput() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let inputURL = fixture.root.appendingPathComponent("input")
        let script = try makeScript(
            in: fixture.root,
            body: """
            stty raw -echo
            dd bs=1 count=7 of="$PROMPTJUICE_TEST_INPUT" 2>/dev/null &
            printf 'Claude Code v2.1.214\\r\\nDo you trust the files in this folder?\\r\\n$\\r\\n'
            wait
            """
        )

        let outcome = session().captureUsage(
            executableURL: script,
            version: .supported(.minimumUsageVersion),
            authentication: .subscription(plan: nil),
            workspaceURL: fixture.workspace,
            environment: testEnvironment(["PROMPTJUICE_TEST_INPUT": inputURL.path])
        )

        XCTAssertEqual(outcome, .workspaceTrustRequired)
        let input = (try? Data(contentsOf: inputURL)) ?? Data()
        XCTAssertTrue(input.isEmpty)
    }

    func testIneligibleVersionAndAuthenticationNeverLaunch() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let markerURL = fixture.root.appendingPathComponent("launched")
        let script = try makeScript(
            in: fixture.root,
            body: "touch \"$PROMPTJUICE_TEST_MARKER\""
        )
        let environment = testEnvironment(["PROMPTJUICE_TEST_MARKER": markerURL.path])

        XCTAssertEqual(
            session().captureUsage(
                executableURL: script,
                version: .updateRequired(
                    installed: ClaudeCodeVersion(major: 2, minor: 1, patch: 207),
                    minimum: .minimumUsageVersion
                ),
                authentication: .subscription(plan: nil),
                workspaceURL: fixture.workspace,
                environment: environment
            ),
            .ineligible(.unsupportedVersion)
        )
        XCTAssertEqual(
            session().captureUsage(
                executableURL: script,
                version: .supported(.minimumUsageVersion),
                authentication: .apiBilling,
                workspaceURL: fixture.workspace,
                environment: environment
            ),
            .ineligible(.authentication)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testOutputLimitTerminatesTheProcessGroup() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let script = try makeScript(
            in: fixture.root,
            body: """
            stty raw -echo
            printf 'Claude Code ready\\r\\n$\\r\\n'
            dd bs=1 count=7 of=/dev/null 2>/dev/null
            yes 0123456789
            """
        )
        let constrainedSession = ClaudePTYSession(
            configuration: testConfiguration(maximumOutputBytes: 256)
        )

        XCTAssertEqual(
            constrainedSession.captureUsage(
                executableURL: script,
                version: .supported(.minimumUsageVersion),
                authentication: .subscription(plan: nil),
                workspaceURL: fixture.workspace,
                environment: testEnvironment()
            ),
            .outputTooLarge
        )
    }

    func testStartupReleaseNoteRateLimitTextDoesNotCompleteUsage() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let script = try makeScript(
            in: fixture.root,
            body: """
            stty raw -echo
            printf 'Claude Code ready\\r\\nFixed a rate limit reached warning\\r\\n$\\r\\n'
            dd bs=1 count=7 of=/dev/null 2>/dev/null
            exit 0
            """
        )

        XCTAssertEqual(
            session().captureUsage(
                executableURL: script,
                version: .supported(.minimumUsageVersion),
                authentication: .subscription(plan: nil),
                workspaceURL: fixture.workspace,
                environment: testEnvironment()
            ),
            .startupOnly
        )
    }

    func testTimeoutAndCancellationKillDescendantProcesses() throws {
        try assertDescendantCleanup(expectedOutcome: .timedOut, cancellationDelay: nil)
        try assertDescendantCleanup(expectedOutcome: .cancelled, cancellationDelay: 0.05)
    }

    func testStartupOnlyOutputRetriesExactlyOnce() throws {
        let fixtureData = Data(
            "Usage\nCurrent session\n42% used\nResets at 3:14 PM\n".utf8
        )
        let retryingTransport = ScriptedClaudeUsageTransport([
            .startupOnly,
            .captured(fixtureData),
        ])
        let probe = ClaudeUsageProbe(transport: retryingTransport)
        let outcome = probe.probe(
            executableURL: URL(fileURLWithPath: "/unused"),
            version: .supported(.minimumUsageVersion),
            authentication: .subscription(plan: nil),
            workspaceURL: URL(fileURLWithPath: "/unused"),
            environment: [:]
        )

        guard case .parsed(let result) = outcome else {
            return XCTFail("Expected parsed result, received \(outcome)")
        }
        XCTAssertEqual(result.reading?.session.usedPercent, 42)
        XCTAssertEqual(retryingTransport.captureCount, 2)

        let nonRetryingTransport = ScriptedClaudeUsageTransport([.timedOut, .captured(fixtureData)])
        XCTAssertEqual(
            ClaudeUsageProbe(transport: nonRetryingTransport).probe(
                executableURL: URL(fileURLWithPath: "/unused"),
                version: .supported(.minimumUsageVersion),
                authentication: .subscription(plan: nil),
                workspaceURL: URL(fileURLWithPath: "/unused"),
                environment: [:]
            ),
            .timedOut
        )
        XCTAssertEqual(nonRetryingTransport.captureCount, 1)
    }

    private func assertDescendantCleanup(
        expectedOutcome: ClaudeUsageTransportOutcome,
        cancellationDelay: TimeInterval?
    ) throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let childPIDURL = fixture.root.appendingPathComponent("child-pid")
        let script = try makeScript(
            in: fixture.root,
            body: """
            sleep 30 &
            printf '%s' "$!" > "$PROMPTJUICE_TEST_CHILD_PID"
            wait
            """
        )
        let startedAt = Date()
        let outcome = session().captureUsage(
            executableURL: script,
            version: .supported(.minimumUsageVersion),
            authentication: .subscription(plan: nil),
            workspaceURL: fixture.workspace,
            environment: testEnvironment(["PROMPTJUICE_TEST_CHILD_PID": childPIDURL.path]),
            isCancelled: {
                guard let cancellationDelay else {
                    return false
                }
                return FileManager.default.fileExists(atPath: childPIDURL.path)
                    && Date().timeIntervalSince(startedAt) >= cancellationDelay
            }
        )

        XCTAssertEqual(outcome, expectedOutcome)
        let childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDURL, encoding: .utf8))
        )
        let deadline = Date().addingTimeInterval(2)
        while kill(childPID, 0) == 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private func session() -> ClaudePTYSession {
        ClaudePTYSession(configuration: testConfiguration())
    }

    private func testConfiguration(maximumOutputBytes: Int = 32 * 1_024) -> ClaudePTYConfiguration {
        ClaudePTYConfiguration(
            startupTimeout: 0.3,
            commandTimeout: 0.4,
            settleInterval: 0.04,
            terminationGrace: 0.1,
            pollInterval: 0.005,
            maximumOutputBytes: maximumOutputBytes
        )
    }

    private func testEnvironment(_ additions: [String: String] = [:]) -> [String: String] {
        var environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        ]
        environment.merge(additions) { _, newValue in newValue }
        return environment
    }

    private func makeFixture() throws -> ProcessFixture {
        let root = try makeTemporaryDirectory()
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertEqual(chmod(workspace.path, 0o700), 0)
        return ProcessFixture(root: root, workspace: workspace)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuice-ClaudePTY-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertEqual(chmod(url.path, 0o700), 0)
        return url
    }

    private func makeScript(in directory: URL, body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o700), 0)
        return url
    }

    private func permissions(of url: URL) -> Int {
        var information = stat()
        XCTAssertEqual(url.path.withCString { lstat($0, &information) }, 0)
        return Int(information.st_mode)
    }
}

private struct ProcessFixture {
    let root: URL
    let workspace: URL

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ScriptedClaudeUsageTransport: ClaudeUsageTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ClaudeUsageTransportOutcome]
    private var count = 0

    init(_ outcomes: [ClaudeUsageTransportOutcome]) {
        self.outcomes = outcomes
    }

    var captureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func captureUsage(
        executableURL _: URL,
        version _: ClaudeVersionGateResult,
        authentication _: ClaudeAuthentication,
        workspaceURL _: URL,
        environment _: [String: String],
        isCancelled _: @escaping @Sendable () -> Bool
    ) -> ClaudeUsageTransportOutcome {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return outcomes.removeFirst()
    }
}
