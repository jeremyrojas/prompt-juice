import Foundation

struct ClaudeCodeVersion: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    static let minimumUsageVersion = ClaudeCodeVersion(major: 2, minor: 1, patch: 208)

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    static func parse(_ data: Data) -> Self? {
        guard data.count <= 4_096,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }

    static func parse(_ text: String) -> Self? {
        let pattern = #"(?<![0-9])([0-9]+)\.([0-9]+)\.([0-9]+)(?:[-+][0-9A-Za-z.-]+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges == 4,
              let majorRange = Range(match.range(at: 1), in: text),
              let minorRange = Range(match.range(at: 2), in: text),
              let patchRange = Range(match.range(at: 3), in: text),
              let major = Int(text[majorRange]),
              let minor = Int(text[minorRange]),
              let patch = Int(text[patchRange]) else {
            return nil
        }

        return ClaudeCodeVersion(major: major, minor: minor, patch: patch)
    }
}

enum ClaudeVersionGateResult: Sendable, Equatable {
    case supported(ClaudeCodeVersion)
    case updateRequired(installed: ClaudeCodeVersion, minimum: ClaudeCodeVersion)
    case unreadable

    static func evaluate(
        _ data: Data,
        minimum: ClaudeCodeVersion = .minimumUsageVersion
    ) -> Self {
        guard let version = ClaudeCodeVersion.parse(data) else {
            return .unreadable
        }

        if version < minimum {
            return .updateRequired(installed: version, minimum: minimum)
        }
        return .supported(version)
    }
}
