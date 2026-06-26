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

    func testPollerDetectsAtomicCacheReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuiceCachePollerTests-\(UUID().uuidString)", isDirectory: true)
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
        try writeCache(usedPercent: 10, to: cacheURL)

        let poller = ClaudeStatusCachePoller(
            cacheURL: cacheURL,
            usesDirectoryWatcher: false,
            queue: DispatchQueue(label: "com.promptjuice.tests.cache-poller")
        )
        let changeDetected = expectation(description: "cache change detected")
        poller.start {
            changeDetected.fulfill()
        }
        defer {
            poller.stop()
        }

        try writeCache(usedPercent: 12, to: cacheURL)

        wait(for: [changeDetected], timeout: 2)
    }

    func testPollerRestartDetectsLaterAtomicCacheReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuiceCachePollerRestartTests-\(UUID().uuidString)", isDirectory: true)
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
        try writeCache(usedPercent: 20, to: cacheURL)

        let poller = ClaudeStatusCachePoller(
            cacheURL: cacheURL,
            usesDirectoryWatcher: false,
            queue: DispatchQueue(label: "com.promptjuice.tests.cache-poller-restart")
        )
        poller.start {}
        poller.stop()

        let changeDetected = expectation(description: "cache change detected after restart")
        poller.start {
            changeDetected.fulfill()
        }
        defer {
            poller.stop()
        }

        try writeCache(usedPercent: 22, to: cacheURL)

        wait(for: [changeDetected], timeout: 2)
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
