import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeLegacyBridgeRemovalTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var bundledScript: URL!
    private let scriptData = Data("#!/usr/bin/env bash\nprintf bridge\n".utf8)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pj-legacy-removal-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        bundledScript = root.appendingPathComponent("bundled.sh")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try scriptData.write(to: bundledScript)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWrappedBridgePlanRestoresCommandAndApplyBacksUpBeforeDeletingScript() throws {
        let remover = makeRemover()
        try installScript(remover)
        let previous = "bash ~/.claude/statusline-command.sh"
        try writeSettings([
            "model": "opus",
            "statusLine": [
                "type": "command",
                "command": "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(previous)' bash '\(remover.installedScriptURL.path)'",
                "refreshInterval": 10,
                "padding": "preserved",
            ],
        ])

        let plan = try XCTUnwrap(remover.makePlan())
        XCTAssertEqual(plan.restoredCommand, previous)
        let restored = try json(plan.restoredSettingsData)
        XCTAssertEqual(restored["model"] as? String, "opus")
        let statusLine = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, previous)
        XCTAssertEqual(statusLine["padding"] as? String, "preserved")
        XCTAssertNil(statusLine["refreshInterval"])

        try remover.apply(plan)

        XCTAssertEqual(try Data(contentsOf: plan.backupURL), plan.originalSettingsData)
        XCTAssertEqual(try Data(contentsOf: remover.settingsURL), plan.restoredSettingsData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: remover.installedScriptURL.path))
    }

    func testAdditiveBridgeRemovalDeletesOnlyStatusLine() throws {
        let remover = makeRemover()
        try installScript(remover)
        try writeSettings([
            "theme": "dark",
            "statusLine": [
                "type": "command",
                "command": "bash '\(remover.installedScriptURL.path)'",
                "refreshInterval": 10,
            ],
        ])

        let plan = try XCTUnwrap(remover.makePlan())
        XCTAssertNil(plan.restoredCommand)
        let restored = try json(plan.restoredSettingsData)
        XCTAssertEqual(restored["theme"] as? String, "dark")
        XCTAssertNil(restored["statusLine"])
    }

    func testOwnershipRequiresExactScriptAndRecognizedCommand() throws {
        let remover = makeRemover()
        try installScript(remover, data: Data("different".utf8))
        try writeSettings([
            "statusLine": ["command": "bash '\(remover.installedScriptURL.path)'"]
        ])
        XCTAssertNil(remover.makePlan())

        try installScript(remover)
        try writeSettings([
            "statusLine": ["command": "bash ~/.claude/user-statusline.sh"]
        ])
        XCTAssertNil(remover.makePlan())
    }

    func testChangedSettingsAbortBeforeBackupOrDeletion() throws {
        let remover = makeRemover()
        try installScript(remover)
        try writeSettings([
            "statusLine": ["command": "bash '\(remover.installedScriptURL.path)'"]
        ])
        let plan = try XCTUnwrap(remover.makePlan())
        try writeSettings(["model": "changed"])

        XCTAssertThrowsError(try remover.apply(plan)) { error in
            XCTAssertEqual(error as? ClaudeLegacyBridgeRemoval.RemovalError, .changedSincePreview)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: remover.installedScriptURL.path))
        XCTAssertEqual(try json(Data(contentsOf: remover.settingsURL))["model"] as? String, "changed")
    }

    private func makeRemover() -> ClaudeLegacyBridgeRemoval {
        ClaudeLegacyBridgeRemoval(
            homeDirectory: home,
            bundledScriptURL: bundledScript,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func installScript(
        _ remover: ClaudeLegacyBridgeRemoval,
        data: Data? = nil
    ) throws {
        try FileManager.default.createDirectory(
            at: remover.installedScriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (data ?? scriptData).write(to: remover.installedScriptURL)
    }

    private func writeSettings(_ object: [String: Any]) throws {
        let settingsURL = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: settingsURL)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
