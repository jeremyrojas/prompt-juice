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

    private func installer(jq: Bool = true) -> ClaudeBridgeInstaller {
        ClaudeBridgeInstaller(homeDirectory: home, bundledScriptURL: nil, jqProbe: { jq })
    }

    private func writeSettings(_ json: String) throws {
        let dir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
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
        XCTAssertTrue(plan.newCommand.contains("PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(original)'"))
        XCTAssertTrue(plan.newCommand.contains(installer().installedScriptURL.path))
    }

    func testJQStatusFlowsIntoPlanAndSummary() throws {
        let missing = try installer(jq: false).makePlan()
        XCTAssertFalse(missing.jqInstalled)
        XCTAssertTrue(missing.summary.contains("jq"))

        let present = try installer(jq: true).makePlan()
        XCTAssertTrue(present.jqInstalled)
        XCTAssertFalse(present.summary.contains("jq isn't installed"))
    }

    func testThrowsWhenSettingsIsNotAnObject() throws {
        try writeSettings("[1, 2, 3]")
        XCTAssertThrowsError(try installer().makePlan()) { error in
            XCTAssertEqual(error as? ClaudeBridgeInstaller.InstallError, .settingsNotAnObject)
        }
    }
}
