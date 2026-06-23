import XCTest
@testable import PromptJuice

final class ClaudeStatusCacheChangeTrackerTests: XCTestCase {
    func testDetectsAtomicCacheReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuiceCacheTrackerTests-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = root
            .appendingPathComponent("ClaudeStatus", isDirectory: true)
            .appendingPathComponent("latest.json")

        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let tracker = ClaudeStatusCacheChangeTracker(cacheURL: cacheURL)

        XCTAssertFalse(tracker.consumeChange())

        try writeCache(usedPercent: 12.5, to: cacheURL)

        XCTAssertTrue(tracker.consumeChange())
        XCTAssertFalse(tracker.consumeChange())

        try writeCache(usedPercent: 18.5, to: cacheURL)

        XCTAssertTrue(tracker.consumeChange())
        XCTAssertFalse(tracker.consumeChange())
    }

    private func writeCache(usedPercent: Double, to cacheURL: URL) throws {
        let temporaryURL = cacheURL
            .deletingLastPathComponent()
            .appendingPathComponent(".latest-\(UUID().uuidString).json")
        let payload = """
        {"rate_limits":{"five_hour":{"used_percentage":\(usedPercent),"resets_at":"1800001800","duration_minutes":300}}}
        """

        try payload.write(to: temporaryURL, atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: cacheURL)
    }
}
