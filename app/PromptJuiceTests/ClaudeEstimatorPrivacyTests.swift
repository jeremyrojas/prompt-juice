import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeEstimatorPrivacyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTypedEstimatorBoundaryRetainsOnlyUsageMetadata() throws {
        let canary = UUID().uuidString
        let input: [String: Any] = [
            "type": "assistant",
            "timestamp": String(Int(now.timeIntervalSince1970)),
            "requestId": "request-privacy-test",
            "isSidechain": true,
            "message": [
                "id": "message-privacy-test",
                "content": [["type": "text", "text": canary]],
                "usage": [
                    "input_tokens": 120,
                    "cache_creation_input_tokens": 30,
                    "cache_read_input_tokens": 20,
                    "output_tokens": 10,
                ],
            ],
            "toolUseResult": ["output": canary],
            "additiveFutureField": canary,
        ]
        let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))

        let entry = try XCTUnwrap(ClaudeLocalLogUsageReader.parseLine(line))

        XCTAssertEqual(entry.timestamp, now)
        XCTAssertEqual(entry.messageID, "message-privacy-test")
        XCTAssertEqual(entry.requestID, "request-privacy-test")
        XCTAssertEqual(entry.totalTokens, 180)
        XCTAssertTrue(entry.isSidechain)
        XCTAssertFalse(String(reflecting: entry).contains(canary))
    }

    func testEstimatorSnapshotContainsOnlyDerivedUsageState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeEstimatorPrivacyTests-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("projects/privacy", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let canary = UUID().uuidString
        let timestamp = now.addingTimeInterval(-30 * 60)
        let input: [String: Any] = [
            "type": "assistant",
            "timestamp": String(Int(timestamp.timeIntervalSince1970)),
            "requestId": "request-derived-state",
            "message": [
                "id": "message-derived-state",
                "content": [["type": "text", "text": canary]],
                "usage": [
                    "input_tokens": 100,
                    "output_tokens": 20,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: input)
        try data.write(to: project.appendingPathComponent("session.jsonl"))
        let reader = ClaudeLocalLogUsageReader(
            projectRoots: [root.appendingPathComponent("projects", isDirectory: true)],
            limits: .unboundedForTests
        )

        let snapshot = try reader.snapshot(now: now)

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.statusDetail, "Estimated from local Claude logs")
        XCTAssertFalse(String(reflecting: snapshot).contains(canary))
    }

    func testTokenArithmeticSaturatesAtIntegerMaximum() throws {
        let input: [String: Any] = [
            "type": "assistant",
            "timestamp": String(Int(now.timeIntervalSince1970)),
            "message": [
                "usage": [
                    "input_tokens": Int.max,
                    "cache_creation_input_tokens": Int.max,
                    "cache_read_input_tokens": Int.max,
                    "output_tokens": Int.max,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: input)
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))

        let entry = try XCTUnwrap(ClaudeLocalLogUsageReader.parseLine(line))
        let block = try XCTUnwrap(ClaudeLocalLogUsageReader.sessionBlocks(from: [entry, entry]).first)

        XCTAssertEqual(entry.totalTokens, Int.max)
        XCTAssertEqual(block.totalTokens, Int.max)
    }

    func testMalformedConversationBearingRecordProducesNoRetainedState() {
        let canary = UUID().uuidString
        let malformed = "{\"type\":\"assistant\",\"message\":{\"content\":\"\(canary)\",\"usage\":"

        XCTAssertNil(ClaudeLocalLogUsageReader.parseLine(malformed))
    }

    func testUnknownErrorsAreReducedToFixedSafeDescriptions() {
        let canary = UUID().uuidString
        let error = CanaryError(value: canary)

        let description = ClaudeUsagePrivacyBoundary.safeDescription(
            for: error,
            fallback: "Claude local estimate unavailable"
        )

        XCTAssertEqual(description, "Claude local estimate unavailable")
        XCTAssertFalse(description.contains(canary))
        XCTAssertEqual(
            ClaudeUsagePrivacyBoundary.safeDescription(
                for: ClaudeUsageError.localLogActiveBlockUnavailable,
                fallback: "unused"
            ),
            "Claude local usage active block unavailable"
        )
    }

    func testClaudeSnapshotPersistenceContainsOnlyDerivedWindowFields() throws {
        let suiteName = "ClaudeEstimatorPrivacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = ClaudeSnapshotCache(defaults: defaults)
        let storageKey = "lastGoodClaudeStatuslineSnapshot"
        let canary = UUID().uuidString

        cache.save(snapshot(source: .claudeLocalLogs, statusDetail: canary))
        XCTAssertNil(defaults.data(forKey: storageKey))

        cache.save(snapshot(source: .claudeUsageCLI, statusDetail: canary))
        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let persistedText = try XCTUnwrap(String(data: data, encoding: .utf8))
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let session = try XCTUnwrap(root["session"] as? [String: Any])

        XCTAssertFalse(persistedText.contains(canary))
        XCTAssertEqual(Set(root.keys), ["session"])
        XCTAssertEqual(
            Set(session.keys),
            ["usedPercent", "resetAt", "durationMinutes", "updatedAt"]
        )
    }

    private func snapshot(
        source: SnapshotSource,
        statusDetail: String
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 42,
                resetAt: now.addingTimeInterval(3_600),
                durationMinutes: 300
            ),
            source: source,
            confidence: source == .claudeLocalLogs ? .estimated : .exact,
            updatedAt: now,
            statusDetail: statusDetail
        )
    }

    private struct CanaryError: LocalizedError {
        let value: String

        var errorDescription: String? {
            value
        }
    }
}
