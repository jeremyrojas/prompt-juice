import XCTest
@testable import PromptJuice

final class ClaudeBridgeInstallerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pj-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func installer() -> ClaudeBridgeInstaller {
        ClaudeBridgeInstaller(homeDirectory: home, bundledScriptURL: nil)
    }

    private func writeSettings(_ json: String) throws {
        let dir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    }

    private func writeSettings(statusLineCommand command: String) throws {
        let dir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: ["statusLine": ["type": "command", "command": command]],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: dir.appendingPathComponent("settings.json"), options: .atomic)
    }

    private func writeInstalledScript() throws {
        let installer = installer()
        try FileManager.default.createDirectory(at: installer.installDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: installer.installedScriptURL, atomically: true, encoding: .utf8)
    }

    private func parse(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAdditiveWhenNoSettings() throws {
        let plan = try installer().makePlan()

        XCTAssertFalse(plan.isWrappingExisting)
        XCTAssertNil(plan.previousCommand)
        XCTAssertTrue(plan.newCommand.hasPrefix("bash '"))
        XCTAssertTrue(plan.newCommand.contains("claude-statusline-bridge.sh"))

        let root = try parse(plan.newSettingsData)
        let statusLine = try XCTUnwrap(root["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, plan.newCommand)
    }

    func testAdditiveShellQuotesInstalledPath() throws {
        let quotedHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pj-bridge-o'clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: quotedHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: quotedHome) }

        let installer = ClaudeBridgeInstaller(homeDirectory: quotedHome, bundledScriptURL: nil)
        let plan = try installer.makePlan()

        XCTAssertEqual(plan.newCommand, "bash \(shellSingleQuoted(installer.installedScriptURL.path))")
    }

    func testWrapsExistingStatusLineAndPreservesOtherKeys() throws {
        try writeSettings(#"""
        {
          "model": "opus",
          "statusLine": { "type": "command", "command": "bash ~/.claude/mine.sh" }
        }
        """#)

        let plan = try installer().makePlan()

        XCTAssertTrue(plan.isWrappingExisting)
        XCTAssertEqual(plan.previousCommand, "bash ~/.claude/mine.sh")
        XCTAssertTrue(plan.newCommand.contains("PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/mine.sh'"))
        XCTAssertTrue(plan.newCommand.contains("claude-statusline-bridge.sh"))

        let root = try parse(plan.newSettingsData)
        XCTAssertEqual(root["model"] as? String, "opus", "unrelated keys must survive")
    }

    func testWrapsExistingStatusLineWithShellQuotedCommand() throws {
        let existing = "printf 'hi there'"
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(existing)" } }
        """#)

        let plan = try installer().makePlan()

        XCTAssertTrue(plan.isWrappingExisting)
        XCTAssertEqual(plan.previousCommand, existing)
        XCTAssertTrue(plan.newCommand.contains("PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND=\(shellSingleQuoted(existing))"))
    }

    func testGeneratedWrappedCommandRunsWithShellQuotedDelegate() throws {
        let existing = "printf 'hi there'"
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(existing)" } }
        """#)

        let installer = installer()
        let plan = try installer.makePlan()
        try FileManager.default.createDirectory(at: installer.installDirectory, withIntermediateDirectories: true)
        try """
        #!/usr/bin/env bash
        printf '%s' "$PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND"
        """.write(to: installer.installedScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installer.installedScriptURL.path)

        let result = try runShell(plan.newCommand)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, existing)
    }

    func testIdempotentWhenAlreadyInstalled() throws {
        let installedCommand = "bash '\(installer().installedScriptURL.path)'"
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(installedCommand)" } }
        """#)

        let plan = try installer().makePlan()

        XCTAssertFalse(plan.isWrappingExisting)
        XCTAssertEqual(plan.newCommand, installedCommand)
    }

    func testBridgeCurrentFalseForStalePath() throws {
        try writeInstalledScript()
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "bash /tmp/old-worktree/scripts/claude-statusline-bridge.sh" } }
        """#)

        XCTAssertFalse(installer().isBridgeCurrent())
    }

    func testBridgeCurrentTrueWhenInstalledScriptExists() throws {
        let installer = installer()
        let installedCommand = "bash '\(installer.installedScriptURL.path)'"
        try writeInstalledScript()
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(installedCommand)" } }
        """#)

        XCTAssertTrue(installer.isBridgeCurrent())
    }

    func testBridgeCurrentFalseWhenInstalledScriptIsMissing() throws {
        let installer = installer()
        let installedCommand = "bash '\(installer.installedScriptURL.path)'"
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(installedCommand)" } }
        """#)

        XCTAssertFalse(installer.isBridgeCurrent())
    }

    func testBridgeCurrentTrueWhenInstalledCommandUsesEscapedPath() throws {
        let quotedHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pj-bridge-o'clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: quotedHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: quotedHome) }

        home = quotedHome
        let installer = installer()
        let installedCommand = "bash \(shellSingleQuoted(installer.installedScriptURL.path))"
        try writeInstalledScript()
        try writeSettings(statusLineCommand: installedCommand)

        XCTAssertTrue(installer.isBridgeCurrent())
        XCTAssertEqual(try installer.makePlan().newCommand, installedCommand)
    }

    func testRewritesStalePromptJuiceBridgeAndPreservesDelegate() throws {
        try writeSettings(#"""
        {
          "statusLine": {
            "type": "command",
            "command": "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/statusline-command.sh' bash /tmp/old-worktree/scripts/claude-statusline-bridge.sh"
          }
        }
        """#)

        let plan = try installer().makePlan()

        XCTAssertTrue(plan.isWrappingExisting)
        XCTAssertEqual(plan.previousCommand, "bash ~/.claude/statusline-command.sh")
        XCTAssertTrue(plan.newCommand.contains("PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/statusline-command.sh'"))
        XCTAssertTrue(plan.newCommand.contains(installer().installedScriptURL.path))
        XCTAssertFalse(plan.newCommand.contains("/tmp/old-worktree"))
    }

    func testRewritesStalePromptJuiceBridgeWithoutDelegate() throws {
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "bash /tmp/old-worktree/scripts/claude-statusline-bridge.sh" } }
        """#)

        let plan = try installer().makePlan()

        XCTAssertFalse(plan.isWrappingExisting)
        XCTAssertNil(plan.previousCommand)
        XCTAssertTrue(plan.newCommand.contains(installer().installedScriptURL.path))
        XCTAssertFalse(plan.newCommand.contains("/tmp/old-worktree"))
    }

    func testWrapsForeignCommandThatSetsPromptJuiceDelegateEnv() throws {
        let original = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/mine.sh' bash ~/.claude/foreign-statusline.sh"
        try writeSettings(#"""
        { "statusLine": { "type": "command", "command": "\#(original)" } }
        """#)

        let plan = try installer().makePlan()

        XCTAssertTrue(plan.isWrappingExisting)
        XCTAssertEqual(plan.previousCommand, original)
        XCTAssertTrue(plan.newCommand.contains("PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND=\(shellSingleQuoted(original))"))
        XCTAssertTrue(plan.newCommand.contains(installer().installedScriptURL.path))
    }

    func testSummaryDoesNotRequireJQ() throws {
        let plan = try installer().makePlan()

        XCTAssertFalse(plan.summary.contains("jq"))
        XCTAssertFalse(plan.summary.contains("brew install"))
    }

    func testThrowsWhenSettingsIsNotAnObject() throws {
        try writeSettings("[1, 2, 3]")
        XCTAssertThrowsError(try installer().makePlan()) { error in
            XCTAssertEqual(error as? ClaudeBridgeInstaller.InstallError, .settingsNotAnObject)
        }
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func runShell(_ command: String) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: output, encoding: .utf8) ?? "",
            String(data: error, encoding: .utf8) ?? ""
        )
    }
}
