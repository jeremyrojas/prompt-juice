import Foundation

struct ClaudeLegacyBridgeRemoval: @unchecked Sendable {
    enum RemovalError: Error, LocalizedError, Equatable {
        case changedSincePreview

        var errorDescription: String? {
            switch self {
            case .changedSincePreview:
                "Claude settings or the legacy bridge changed after the preview. PromptJuice left everything untouched."
            }
        }
    }

    struct Plan: Equatable {
        let settingsURL: URL
        let installedScriptURL: URL
        let backupURL: URL
        let restoredCommand: String?
        let originalSettingsData: Data
        let originalScriptData: Data
        let restoredSettingsData: Data
    }

    private static let defaultBundledScriptURL = Bundle.main.url(
        forResource: "claude-statusline-bridge",
        withExtension: "sh"
    )

    let homeDirectory: URL
    let bundledScriptURL: URL?
    let fileManager: FileManager
    let now: @Sendable () -> Date

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledScriptURL: URL? = Self.defaultBundledScriptURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.homeDirectory = homeDirectory
        self.bundledScriptURL = bundledScriptURL
        self.fileManager = fileManager
        self.now = now
    }

    var settingsURL: URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    var installedScriptURL: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/PromptJuice", isDirectory: true)
            .appendingPathComponent("claude-statusline-bridge.sh")
    }

    func makePlan() -> Plan? {
        guard let bundledScriptURL,
              let bundledScriptData = try? Data(contentsOf: bundledScriptURL),
              let installedScriptData = try? Data(contentsOf: installedScriptURL),
              installedScriptData == bundledScriptData,
              let settingsData = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: settingsData),
              var root = object as? [String: Any],
              var statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String,
              let ownership = ownedCommand(command) else {
            return nil
        }

        switch ownership {
        case .wrapped(let previousCommand):
            statusLine["type"] = "command"
            statusLine["command"] = previousCommand
            statusLine.removeValue(forKey: "refreshInterval")
            root["statusLine"] = statusLine
        case .additive:
            root.removeValue(forKey: "statusLine")
        }

        guard let restoredSettingsData = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return nil
        }

        return Plan(
            settingsURL: settingsURL,
            installedScriptURL: installedScriptURL,
            backupURL: backupURL(),
            restoredCommand: ownership.previousCommand,
            originalSettingsData: settingsData,
            originalScriptData: installedScriptData,
            restoredSettingsData: restoredSettingsData
        )
    }

    func apply(_ plan: Plan) throws {
        guard plan.settingsURL == settingsURL,
              plan.installedScriptURL == installedScriptURL,
              (try? Data(contentsOf: settingsURL)) == plan.originalSettingsData,
              (try? Data(contentsOf: installedScriptURL)) == plan.originalScriptData else {
            throw RemovalError.changedSincePreview
        }

        try plan.originalSettingsData.write(to: plan.backupURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: plan.backupURL.path
        )
        try plan.restoredSettingsData.write(to: settingsURL, options: [.atomic])
        try fileManager.removeItem(at: installedScriptURL)
    }

    private enum Ownership {
        case wrapped(String)
        case additive

        var previousCommand: String? {
            switch self {
            case .wrapped(let command): command
            case .additive: nil
            }
        }
    }

    private func ownedCommand(_ command: String) -> Ownership? {
        let quotedBridge = "bash '\(installedScriptURL.path)'"
        if command == quotedBridge || command == "bash \(installedScriptURL.path)" {
            return .additive
        }

        let prefix = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND="
        guard command.hasPrefix(prefix),
              command.hasSuffix(quotedBridge),
              let parsed = parseShellSingleQuotedValue(
                in: command,
                from: command.index(command.startIndex, offsetBy: prefix.count)
              ),
              command[parsed.endIndex...].trimmingCharacters(in: .whitespaces) == quotedBridge else {
            return nil
        }
        return .wrapped(parsed.value)
    }

    private func parseShellSingleQuotedValue(
        in command: String,
        from startIndex: String.Index
    ) -> (value: String, endIndex: String.Index)? {
        guard startIndex < command.endIndex, command[startIndex] == "'" else {
            return nil
        }
        var value = ""
        var scanIndex = command.index(after: startIndex)
        while let closingQuote = command[scanIndex...].firstIndex(of: "'") {
            value.append(contentsOf: command[scanIndex..<closingQuote])
            var cursor = command.index(after: closingQuote)
            if command[cursor...].hasPrefix("\\''") {
                value.append("'")
                cursor = command.index(cursor, offsetBy: 3)
                scanIndex = cursor
                continue
            }
            return (value, cursor)
        }
        return nil
    }

    private func backupURL() -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: now())
            .replacingOccurrences(of: ":", with: "-")
        return settingsURL.deletingLastPathComponent().appendingPathComponent(
            "settings.json.promptjuice-backup-\(timestamp)"
        )
    }
}
