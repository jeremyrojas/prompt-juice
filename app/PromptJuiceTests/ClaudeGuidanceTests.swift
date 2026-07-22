import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeGuidanceTests: XCTestCase {
    func testContentUsesExactCommandsForEveryKnownProvenance() {
        let access = ClaudeAccessState.updateRequired(
            installed: version(2, 0, 14),
            minimum: .minimumUsageVersion
        )
        let expected: [(ClaudeInstallationProvenance, String)] = [
            (.native, "claude update"),
            (.homebrewAppleSilicon, "brew upgrade claude-code"),
            (.homebrewIntel, "brew upgrade claude-code"),
            (.npmGlobal, "npm install -g @anthropic-ai/claude-code@latest"),
        ]

        for (provenance, command) in expected {
            let content = ClaudeGuidanceContent.make(
                journey: .update,
                access: access,
                location: location(provenance: provenance)
            )
            XCTAssertEqual(content.commands, [ClaudeGuidanceCommand(label: nil, value: command)])
            XCTAssertEqual(content.primaryCommand, command)
            XCTAssertEqual(content.primaryButtonTitle, "Copy and Open Terminal")
            XCTAssertEqual(content.versionStatus, "Current version 2.0.14 · required 2.1.208")
        }

        XCTAssertEqual(
            ClaudeGuidanceContent.make(journey: .install, access: .cliMissing, location: nil).primaryCommand,
            "curl -fsSL https://claude.ai/install.sh | bash"
        )
        XCTAssertEqual(
            ClaudeGuidanceContent.make(
                journey: .signIn,
                access: .signedOut(reason: .initial),
                location: nil
            ).primaryCommand,
            "claude auth login"
        )
    }

    func testUnknownProvenanceShowsPathAndThreeCopyableAlternativesWithoutPrimaryCopy() {
        for provenance in [ClaudeInstallationProvenance.customSymlink, .unknown] {
            let content = ClaudeGuidanceContent.make(
                journey: .update,
                access: .updateRequired(
                    installed: version(2, 0, 14),
                    minimum: .minimumUsageVersion
                ),
                location: location(provenance: provenance)
            )

            XCTAssertEqual(content.executablePath, "/opt/tools/bin/claude")
            XCTAssertEqual(content.commands.map(\.value), [
                "claude update",
                "brew upgrade claude-code",
                "npm install -g @anthropic-ai/claude-code@latest",
            ])
            XCTAssertEqual(content.commands.map(\.label), ["Native install", "Homebrew", "npm"])
            XCTAssertNil(content.primaryCommand)
            XCTAssertEqual(content.primaryButtonTitle, "Open Terminal")
        }
    }

    func testSignInRecheckRunsAuthStatusOnly() throws {
        let runner = GuidanceRunner()
        let checker = checker(runner: runner)

        let result = checker.check(journey: .signIn)

        XCTAssertEqual(result.access, .subscription(plan: "max"))
        XCTAssertEqual(runner.recordedArguments, [["auth", "status"]])
    }

    func testInstallAndUpdateRechecksRunVersionThenAuthStatus() throws {
        for journey in [ClaudeGuidanceJourney.install, .update] {
            let runner = GuidanceRunner()
            let result = checker(runner: runner).check(journey: journey)

            XCTAssertEqual(result.access, .subscription(plan: "max"))
            XCTAssertEqual(runner.recordedArguments, [["--version"], ["auth", "status"]])
        }
    }

    func testInstallRecheckAdvancesInPlaceToSignIn() {
        let result = ClaudeGuidanceCheckResult(
            access: .signedOut(reason: .initial),
            location: location(provenance: .native)
        )

        XCTAssertFalse(result.completesJourney)
        XCTAssertEqual(result.journey(after: .install), .signIn)
    }

    func testActivationRecheckRequiresThirtySeconds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var debouncer = ClaudeGuidanceRecheckDebouncer(lastCheckAt: start)

        XCTAssertFalse(debouncer.shouldCheck(at: start.addingTimeInterval(29.99)))
        XCTAssertTrue(debouncer.shouldCheck(at: start.addingTimeInterval(30)))
        XCTAssertFalse(debouncer.shouldCheck(at: start.addingTimeInterval(59)))
        XCTAssertTrue(debouncer.shouldCheck(at: start.addingTimeInterval(60)))
    }

    func testWorkspaceTrustPresentationAndScopedRecheck() throws {
        let presentation = ClaudeUsagePresentation.resolve(
            access: .workspaceTrustRequired,
            refresh: .idle,
            snapshot: nil,
            isEnabled: true,
            now: Date()
        )
        XCTAssertEqual(presentation.state, .workspaceTrustRequired)
        XCTAssertEqual(presentation.rowStatus, "Workspace trust needed")
        XCTAssertEqual(presentation.settingsAction, .journey(.trustWorkspace))

        let runner = GuidanceRunner()
        let trust = GuidanceTrustProbe(outcome: .ready)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pj-guidance-trust-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executableLocation = location(provenance: .native)
        let checker = SystemClaudeGuidanceChecker(
            locate: { executableLocation },
            versionProbe: ClaudeVersionProbe(runner: runner),
            authProbe: ClaudeAuthProbe(
                runner: runner,
                configurationReader: ClaudeAuthConfigurationReader(
                    homeDirectory: root,
                    managedSettingsDirectory: root.appendingPathComponent("managed", isDirectory: true),
                    managedPreferenceDocuments: []
                )
            ),
            trustProbe: trust,
            workspace: ClaudeProbeWorkspace(url: root.appendingPathComponent("Probe/Workspace")),
            environment: [:]
        )

        let result = checker.check(journey: .trustWorkspace)

        XCTAssertEqual(result.access, .subscription(plan: "max"))
        XCTAssertEqual(runner.recordedArguments, [["--version"], ["auth", "status"]])
        XCTAssertEqual(trust.checkCount, 1)
    }

    private func checker(runner: GuidanceRunner) -> SystemClaudeGuidanceChecker {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pj-guidance-empty-home", isDirectory: true)
        let executableLocation = location(provenance: .native)
        return SystemClaudeGuidanceChecker(
            locate: { executableLocation },
            versionProbe: ClaudeVersionProbe(runner: runner),
            authProbe: ClaudeAuthProbe(
                runner: runner,
                configurationReader: ClaudeAuthConfigurationReader(
                    homeDirectory: home,
                    managedSettingsDirectory: home.appendingPathComponent("managed", isDirectory: true),
                    managedPreferenceDocuments: []
                )
            ),
            environment: [:]
        )
    }

    private func location(provenance: ClaudeInstallationProvenance) -> ClaudeExecutableLocation {
        ClaudeExecutableLocation(
            invokedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
            resolvedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
            provenance: provenance
        )
    }

    private func version(_ major: Int, _ minor: Int, _ patch: Int) -> ClaudeCodeVersion {
        ClaudeCodeVersion(major: major, minor: minor, patch: patch)
    }
}

private final class GuidanceRunner: ClaudeCLICommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var arguments: [[String]] = []

    var recordedArguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return arguments
    }

    func run(
        executableURL _: URL,
        arguments: [String],
        environment _: [String: String],
        timeout _: TimeInterval
    ) throws -> ClaudeCLICommandResult {
        lock.lock()
        self.arguments.append(arguments)
        lock.unlock()

        if arguments == ["--version"] {
            return ClaudeCLICommandResult(
                standardOutput: Data("2.1.214 (Claude Code)\n".utf8),
                terminationStatus: 0
            )
        }

        return ClaudeCLICommandResult(
            standardOutput: Data(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}"#.utf8),
            terminationStatus: 0
        )
    }
}

private final class GuidanceTrustProbe: ClaudeWorkspaceTrustChecking, @unchecked Sendable {
    let outcome: ClaudeWorkspaceTrustOutcome
    private let lock = NSLock()
    private var count = 0

    init(outcome: ClaudeWorkspaceTrustOutcome) {
        self.outcome = outcome
    }

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func checkWorkspaceTrust(
        executableURL _: URL,
        workspaceURL _: URL,
        environment _: [String: String]
    ) -> ClaudeWorkspaceTrustOutcome {
        lock.lock()
        count += 1
        lock.unlock()
        return outcome
    }
}
