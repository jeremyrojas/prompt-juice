import Foundation

enum ClaudeInstallationProvenance: String, Codable, Sendable, Equatable {
    case native
    case homebrewAppleSilicon
    case homebrewIntel
    case npmGlobal
    case customSymlink
    case unknown

    var updateCommand: String? {
        switch self {
        case .native:
            return "claude update"
        case .homebrewAppleSilicon, .homebrewIntel:
            return "brew upgrade claude-code"
        case .npmGlobal:
            return "npm install -g @anthropic-ai/claude-code@latest"
        case .customSymlink, .unknown:
            return nil
        }
    }

    static func detect(invokedURL: URL, resolvedURL: URL) -> Self {
        let invokedPath = invokedURL.standardizedFileURL.path
        let resolvedPath = resolvedURL.standardizedFileURL.path

        if resolvedPath.contains("/node_modules/@anthropic-ai/claude-code/") {
            return .npmGlobal
        }

        if invokedPath.hasSuffix("/.local/bin/claude"),
           resolvedPath.contains("/.local/share/claude/versions/"),
           resolvedPath.hasSuffix("/claude") {
            return .native
        }

        if isHomebrewPath(
            invokedPath: invokedPath,
            resolvedPath: resolvedPath,
            prefix: "/opt/homebrew"
        ) {
            return .homebrewAppleSilicon
        }

        if isHomebrewPath(
            invokedPath: invokedPath,
            resolvedPath: resolvedPath,
            prefix: "/usr/local"
        ) {
            return .homebrewIntel
        }

        if invokedPath != resolvedPath {
            return .customSymlink
        }

        return .unknown
    }

    private static func isHomebrewPath(
        invokedPath: String,
        resolvedPath: String,
        prefix: String
    ) -> Bool {
        guard invokedPath == "\(prefix)/bin/claude" || resolvedPath.hasPrefix("\(prefix)/") else {
            return false
        }

        return resolvedPath.contains("/Caskroom/claude-code/")
            || resolvedPath.contains("/Cellar/claude-code/")
            || resolvedPath == "\(prefix)/bin/claude"
    }
}

struct ClaudeExecutableLocation: Sendable, Equatable {
    let invokedURL: URL
    let resolvedURL: URL
    let provenance: ClaudeInstallationProvenance
}

struct ClaudeExecutableLocator {
    static let overrideEnvironmentKey = "PROMPTJUICE_CLAUDE_PATH"

    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeExecutableLocation? {
        var candidates: [String] = []

        if let override = environment[overrideEnvironmentKey] {
            candidates.append(override)
        }

        candidates.append(
            homeDirectory
                .appendingPathComponent(".local/bin/claude", isDirectory: false)
                .path
        )
        candidates.append("/opt/homebrew/bin/claude")
        candidates.append("/usr/local/bin/claude")

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":", omittingEmptySubsequences: false).compactMap {
                let directory = String($0)
                guard directory.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent("claude", isDirectory: false)
                    .path
            })
        }

        var visited: Set<String> = []
        for path in candidates {
            guard path.hasPrefix("/") else {
                continue
            }

            let invokedURL = URL(fileURLWithPath: path).standardizedFileURL
            guard visited.insert(invokedURL.path).inserted,
                  isAllowedMacOSCLIPath(invokedURL.path),
                  fileManager.isExecutableFile(atPath: invokedURL.path) else {
                continue
            }

            let resolvedURL = invokedURL.resolvingSymlinksInPath().standardizedFileURL
            guard isAllowedMacOSCLIPath(resolvedURL.path),
                  fileManager.isExecutableFile(atPath: resolvedURL.path) else {
                continue
            }

            return ClaudeExecutableLocation(
                invokedURL: invokedURL,
                resolvedURL: resolvedURL,
                provenance: ClaudeInstallationProvenance.detect(
                    invokedURL: invokedURL,
                    resolvedURL: resolvedURL
                )
            )
        }

        return nil
    }

    static func isAllowedMacOSCLIPath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        return !normalized.contains("/claude.app/contents/")
            && !normalized.contains("/claude desktop.app/contents/")
    }
}
