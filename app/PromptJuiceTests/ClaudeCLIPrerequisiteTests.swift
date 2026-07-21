import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeCLIPrerequisiteTests: XCTestCase {
    func testVersionFixturesCoverMinimumBoundaryAndAcceptedShapes() throws {
        let cases: [(String, ClaudeVersionGateResult)] = [
            ("current", .supported(version(2, 1, 211))),
            ("minimum", .supported(.minimumUsageVersion)),
            (
                "below-minimum",
                .updateRequired(installed: version(2, 1, 207), minimum: .minimumUsageVersion)
            ),
            (
                "older",
                .updateRequired(installed: version(2, 0, 14), minimum: .minimumUsageVersion)
            ),
            ("prefixed", .supported(version(2, 1, 211))),
            ("malformed", .unreadable)
        ]

        for (fixture, expected) in cases {
            let data = try fixtureData("Version/\(fixture).txt")
            XCTAssertEqual(ClaudeVersionGateResult.evaluate(data), expected, fixture)
        }

        XCTAssertEqual(
            ClaudeVersionGateResult.evaluate(try fixtureData("Live/version-2.1.214.txt")),
            .supported(version(2, 1, 214))
        )
        XCTAssertEqual(ClaudeCodeVersion.parse("2.1.208-beta.1"), .minimumUsageVersion)
        XCTAssertNil(ClaudeCodeVersion.parse(Data(repeating: 0x31, count: 4_097)))
    }

    func testProvenanceFixtureCoversEveryInstallationShape() throws {
        struct Fixture: Decodable {
            struct Case: Decodable {
                let id: String
                let resolvedPath: String
                let invokedPath: String
            }
            let cases: [Case]
        }

        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: fixtureData("Provenance/outcomes.json")
        )
        let expected: [String: ClaudeInstallationProvenance] = [
            "native": .native,
            "homebrew-apple-silicon": .homebrewAppleSilicon,
            "homebrew-intel": .homebrewIntel,
            "npm-global": .npmGlobal,
            "custom-symlink": .customSymlink,
            "unknown": .unknown
        ]

        XCTAssertEqual(Set(fixture.cases.map(\.id)), Set(expected.keys))
        for item in fixture.cases {
            let detected = ClaudeInstallationProvenance.detect(
                invokedURL: URL(fileURLWithPath: item.invokedPath),
                resolvedURL: URL(fileURLWithPath: item.resolvedPath)
            )
            XCTAssertEqual(detected, expected[item.id], item.id)
        }

        XCTAssertEqual(ClaudeInstallationProvenance.native.updateCommand, "claude update")
        XCTAssertEqual(
            ClaudeInstallationProvenance.homebrewAppleSilicon.updateCommand,
            "brew upgrade claude-code"
        )
        XCTAssertEqual(
            ClaudeInstallationProvenance.npmGlobal.updateCommand,
            "npm install -g @anthropic-ai/claude-code@latest"
        )
        XCTAssertNil(ClaudeInstallationProvenance.customSymlink.updateCommand)
        XCTAssertNil(ClaudeInstallationProvenance.unknown.updateCommand)
    }

    func testLocatorUsesSafeAbsoluteCandidatesAndResolvesSymlinks() throws {
        try withTemporaryDirectory { root in
            let target = root.appendingPathComponent("versions/2.1.214/claude")
            try makeExecutable(target, body: "#!/bin/sh\nexit 0\n")
            let override = root.appendingPathComponent("bin/claude")
            try FileManager.default.createDirectory(
                at: override.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: override,
                withDestinationURL: target
            )

            let location = try XCTUnwrap(
                ClaudeExecutableLocator.locate(
                    environment: [
                        ClaudeExecutableLocator.overrideEnvironmentKey: override.path,
                        "PATH": "relative:/usr/bin"
                    ],
                    homeDirectory: root.appendingPathComponent("home")
                )
            )

            XCTAssertEqual(location.invokedURL.path, override.path)
            XCTAssertEqual(location.resolvedURL.path, target.path)
            XCTAssertEqual(location.provenance, .customSymlink)
        }

        XCTAssertFalse(
            ClaudeExecutableLocator.isAllowedMacOSCLIPath(
                "/Applications/Claude.app/Contents/Resources/linux/claude"
            )
        )
        XCTAssertTrue(
            ClaudeExecutableLocator.isAllowedMacOSCLIPath("/opt/homebrew/bin/claude")
        )
    }

    func testLocatorFindsNativeCandidateWithoutTerminalPath() throws {
        try withTemporaryDirectory { root in
            let executable = root.appendingPathComponent(".local/bin/claude")
            try makeExecutable(executable, body: "#!/bin/sh\nexit 0\n")

            let location = try XCTUnwrap(
                ClaudeExecutableLocator.locate(
                    environment: [:],
                    homeDirectory: root
                )
            )
            XCTAssertEqual(location.invokedURL.path, executable.path)
        }
    }

    func testAuthFixturesMapToAllRequiredCategories() throws {
        let cases: [(String, ClaudeAuthentication)] = [
            ("subscription", .subscription(plan: "max")),
            ("additive-harmless-fields", .subscription(plan: "max")),
            ("api-billing", .apiBilling),
            ("external-bedrock", .externalProvider(.bedrock)),
            ("external-vertex", .externalProvider(.vertex)),
            ("external-foundry", .externalProvider(.foundry)),
            ("external-gateway", .externalProvider(.gateway)),
            ("signed-out-initial", .signedOut(reason: .initial)),
            ("reauth-expired", .signedOut(reason: .reauthenticationRequired)),
            ("reauth-revoked", .signedOut(reason: .reauthenticationRequired)),
            ("missing-required-field", .unsupported),
            ("unknown-auth-method", .unsupported),
            ("unknown-api-provider", .unsupported),
            ("unknown-subscription-type", .unsupported),
            ("malformed", .checkFailed)
        ]

        for (fixture, expected) in cases {
            XCTAssertEqual(
                ClaudeAuthClassifier.classify(
                    authStatusData: try fixtureData("Auth/\(fixture).json")
                ),
                expected,
                fixture
            )
        }

        XCTAssertEqual(
            ClaudeAuthClassifier.classify(
                authStatusData: try fixtureData("Live/auth-status-subscription.json")
            ),
            .subscription(plan: "max")
        )
    }

    func testBillingEvidenceOverridesSubscriptionFailClosed() throws {
        let subscription = try fixtureData("Auth/subscription.json")
        let cases: [([String: String], ClaudeAuthentication)] = [
            (["ANTHROPIC_API_KEY": "fixture-api-key"], .apiBilling),
            (["ANTHROPIC_AUTH_TOKEN": "fixture-auth-token"], .apiBilling),
            (["CLAUDE_CODE_USE_BEDROCK": "1"], .externalProvider(.bedrock)),
            (["CLAUDE_CODE_USE_MANTLE": "true"], .externalProvider(.bedrock)),
            (["CLAUDE_CODE_USE_VERTEX": "1"], .externalProvider(.vertex)),
            (["CLAUDE_CODE_USE_FOUNDRY": "yes"], .externalProvider(.foundry)),
            (["ANTHROPIC_BASE_URL": "https://gateway.example.test"], .externalProvider(.gateway)),
            (["CLAUDE_CODE_OAUTH_TOKEN": "fixture-oauth-token"], .subscription(plan: "max")),
            (["CLAUDE_CODE_USE_ANTHROPIC_AWS": "1"], .unsupported),
            (["ANTHROPIC_AWS_WORKSPACE_ID": "fixture-workspace"], .unsupported),
            (["HTTPS_PROXY": "https://proxy.example.test"], .unsupported),
            (["https_proxy": "https://proxy.example.test"], .unsupported),
            (["CLAUDE_CODE_USE_VERTEX": "sometimes"], .unsupported),
            (
                ["ANTHROPIC_API_KEY": "fixture-api-key", "CLAUDE_CODE_USE_VERTEX": "1"],
                .unsupported
            )
        ]

        for (environment, expected) in cases {
            let evidence = ClaudeBillingEvidenceScanner.scan(environment: environment)
            XCTAssertEqual(
                ClaudeAuthClassifier.classify(
                    authStatusData: subscription,
                    evidence: evidence
                ),
                expected,
                environment.keys.sorted().joined(separator: ",")
            )
        }
    }

    func testSettingsAndManagedSettingsEvidenceIsNarrowAndFailClosed() throws {
        let subscription = try fixtureData("Auth/subscription.json")
        let documents: [(Data, ClaudeAuthentication)] = [
            (
                Data(#"{"apiKeyHelper":"/usr/local/bin/key-helper"}"#.utf8),
                .apiBilling
            ),
            (
                Data(#"{"env":{"CLAUDE_CODE_USE_VERTEX":"1"}}"#.utf8),
                .externalProvider(.vertex)
            ),
            (
                Data(#"{"managedSettings":{"env":{"CLAUDE_CODE_USE_FOUNDRY":"1"}}}"#.utf8),
                .externalProvider(.foundry)
            ),
            (
                Data(#"{"policyHelper":{"path":"/usr/local/bin/policy"}}"#.utf8),
                .unsupported
            ),
            (Data(#"{"env":"future-shape"}"#.utf8), .unsupported),
            (Data(#"{"apiKeyHelper":{"future":"shape"}}"#.utf8), .unsupported),
            (Data(#"{"env":{"ANTHROPIC_API_KEY":42}}"#.utf8), .unsupported),
            (Data(#"{"env": "#.utf8), .unsupported)
        ]

        for (document, expected) in documents {
            let evidence = ClaudeBillingEvidenceScanner.scan(
                environment: [:],
                settingsDocuments: [document]
            )
            XCTAssertEqual(
                ClaudeAuthClassifier.classify(
                    authStatusData: subscription,
                    evidence: evidence
                ),
                expected
            )
        }

        let failedRead = ClaudeBillingEvidenceScanner.scan(
            environment: [:],
            settingsReadFailed: true
        )
        XCTAssertEqual(
            ClaudeAuthClassifier.classify(
                authStatusData: subscription,
                evidence: failedRead
            ),
            .unsupported
        )

        let secret = "fixture-secret-value-that-must-not-survive"
        let evidence = ClaudeBillingEvidenceScanner.scan(
            environment: ["ANTHROPIC_API_KEY": secret]
        )
        XCTAssertFalse(String(reflecting: evidence).contains(secret))
    }

    func testConfigurationReaderScansUserAndManagedFilesWithoutFollowingSymlinks() throws {
        try withTemporaryDirectory { root in
            let home = root.appendingPathComponent("home")
            let config = home.appendingPathComponent(".claude")
            let managed = root.appendingPathComponent("managed")
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
            try Data(#"{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}"#.utf8).write(
                to: config.appendingPathComponent("settings.json")
            )

            let reader = ClaudeAuthConfigurationReader(
                homeDirectory: home,
                managedSettingsDirectory: managed,
                managedPreferenceDocuments: []
            )
            let classification = ClaudeAuthClassifier.classify(
                authStatusData: try fixtureData("Auth/subscription.json"),
                evidence: reader.evidence(environment: [:])
            )
            XCTAssertEqual(classification, .externalProvider(.bedrock))

            try FileManager.default.removeItem(at: config.appendingPathComponent("settings.json"))
            let target = root.appendingPathComponent("outside-settings.json")
            try Data(#"{}"#.utf8).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: config.appendingPathComponent("settings.json"),
                withDestinationURL: target
            )

            let symlinkClassification = ClaudeAuthClassifier.classify(
                authStatusData: try fixtureData("Auth/subscription.json"),
                evidence: reader.evidence(environment: [:])
            )
            XCTAssertEqual(symlinkClassification, .unsupported)
        }
    }

    func testConfigurationReaderScansManagedPreferenceSettings() throws {
        try withTemporaryDirectory { root in
            let reader = ClaudeAuthConfigurationReader(
                homeDirectory: root.appendingPathComponent("home"),
                managedSettingsDirectory: root.appendingPathComponent("managed"),
                managedPreferenceDocuments: [
                    Data(#"{"env":{"CLAUDE_CODE_USE_FOUNDRY":"1"}}"#.utf8)
                ]
            )

            XCTAssertEqual(
                ClaudeAuthClassifier.classify(
                    authStatusData: try fixtureData("Auth/subscription.json"),
                    evidence: reader.evidence(environment: [:])
                ),
                .externalProvider(.foundry)
            )
        }
    }

    func testSignedOutOAuthTokenMeansReauthenticationAndUsageGateIsExclusive() throws {
        let evidence = ClaudeBillingEvidenceScanner.scan(
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "fixture-oauth-token"]
        )
        XCTAssertEqual(
            ClaudeAuthClassifier.classify(
                authStatusData: try fixtureData("Auth/signed-out-initial.json"),
                evidence: evidence
            ),
            .signedOut(reason: .reauthenticationRequired)
        )

        XCTAssertTrue(ClaudeAuthentication.subscription(plan: "max").permitsUsageProbe)
        XCTAssertFalse(ClaudeAuthentication.apiBilling.permitsUsageProbe)
        XCTAssertFalse(ClaudeAuthentication.externalProvider(.bedrock).permitsUsageProbe)
        XCTAssertFalse(ClaudeAuthentication.signedOut(reason: .initial).permitsUsageProbe)
        XCTAssertFalse(ClaudeAuthentication.unsupported.permitsUsageProbe)
        XCTAssertFalse(ClaudeAuthentication.checkFailed.permitsUsageProbe)
    }

    func testNoninteractiveProbesUseExactCommandsAndRespectExitStatus() throws {
        try withTemporaryDirectory { root in
            let record = root.appendingPathComponent("arguments.txt")
            let executable = root.appendingPathComponent("claude-fixture")
            try makeExecutable(
                executable,
                body: """
                #!/bin/sh
                printf '%s' "$*" > "$FAKE_RECORD"
                if [ "$1" = "--version" ]; then
                  printf '%s\n' '2.1.214 (Claude Code)'
                  exit 0
                fi
                if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
                  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}'
                  exit 0
                fi
                exit 9
                """
            )

            let environment = ["FAKE_RECORD": record.path]
            XCTAssertEqual(
                ClaudeVersionProbe().probe(
                    executableURL: executable,
                    environment: environment
                ),
                .supported(version(2, 1, 214))
            )
            XCTAssertEqual(try String(contentsOf: record, encoding: .utf8), "--version")

            let emptyHome = root.appendingPathComponent("home")
            let emptyManaged = root.appendingPathComponent("managed")
            let authProbe = ClaudeAuthProbe(
                configurationReader: ClaudeAuthConfigurationReader(
                    homeDirectory: emptyHome,
                    managedSettingsDirectory: emptyManaged,
                    managedPreferenceDocuments: []
                )
            )
            XCTAssertEqual(
                authProbe.probe(
                    executableURL: executable,
                    environment: environment
                ),
                .subscription(plan: "max")
            )
            XCTAssertEqual(try String(contentsOf: record, encoding: .utf8), "auth status")
        }

        let signedOutRunner = StubClaudeCommandRunner(
            result: .success(
                ClaudeCLICommandResult(
                    standardOutput: try fixtureData("Auth/signed-out-initial.json"),
                    terminationStatus: 1
                )
            )
        )
        XCTAssertEqual(
            ClaudeAuthProbe(
                runner: signedOutRunner,
                configurationReader: ClaudeAuthConfigurationReader(
                    homeDirectory: URL(fileURLWithPath: "/path/that/does/not/exist"),
                    managedSettingsDirectory: URL(fileURLWithPath: "/another/missing/path"),
                    managedPreferenceDocuments: []
                )
            ).probe(
                executableURL: URL(fileURLWithPath: "/fixture/claude"),
                environment: [:]
            ),
            .signedOut(reason: .initial)
        )
    }

    func testCommandRunnerBoundsOutputAndTimeout() throws {
        try withTemporaryDirectory { root in
            let oversized = root.appendingPathComponent("oversized")
            try makeExecutable(
                oversized,
                body: "#!/bin/sh\nprintf '%0200d' 0\n"
            )
            XCTAssertThrowsError(
                try ClaudeCLICommandRunner(maximumOutputBytes: 32).run(
                    executableURL: oversized,
                    arguments: [],
                    environment: [:],
                    timeout: 1
                )
            ) { error in
                XCTAssertEqual(error as? ClaudeCLICommandError, .outputTooLarge)
            }

            let hanging = root.appendingPathComponent("hanging")
            try makeExecutable(hanging, body: "#!/bin/sh\nwhile :; do :; done\n")
            XCTAssertThrowsError(
                try ClaudeCLICommandRunner().run(
                    executableURL: hanging,
                    arguments: [],
                    environment: [:],
                    timeout: 0.05
                )
            ) { error in
                XCTAssertEqual(error as? ClaudeCLICommandError, .timedOut)
            }
        }
    }

    private func fixtureData(_ path: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.resourceURL)
            .appendingPathComponent("Fixtures/Claude/\(path)")
        return try Data(contentsOf: url)
    }

    private func version(_ major: Int, _ minor: Int, _ patch: Int) -> ClaudeCodeVersion {
        ClaudeCodeVersion(major: major, minor: minor, patch: patch)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCLIPrerequisiteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeExecutable(_ url: URL, body: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}

private struct StubClaudeCommandRunner: ClaudeCLICommandRunning {
    let result: Result<ClaudeCLICommandResult, ClaudeCLICommandError>

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> ClaudeCLICommandResult {
        try result.get()
    }
}
