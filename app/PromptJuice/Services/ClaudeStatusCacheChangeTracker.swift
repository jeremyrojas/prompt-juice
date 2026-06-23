import Foundation

final class ClaudeStatusCacheChangeTracker {
    private struct CacheSignature: Equatable {
        let fileID: UInt64?
        let size: UInt64?
        let modificationDate: Date?
    }

    private let cacheURL: URL
    private let fileManager: FileManager
    private var lastSignature: CacheSignature?

    init(
        cacheURL: URL = ClaudeStatuslineSnapshotReader.defaultCacheURL(),
        fileManager: FileManager = .default
    ) {
        self.cacheURL = cacheURL
        self.fileManager = fileManager
        lastSignature = Self.signature(for: cacheURL, fileManager: fileManager)
    }

    func consumeChange() -> Bool {
        let currentSignature = Self.signature(for: cacheURL, fileManager: fileManager)
        defer {
            lastSignature = currentSignature
        }

        return currentSignature != lastSignature
    }

    func reset() {
        lastSignature = Self.signature(for: cacheURL, fileManager: fileManager)
    }

    private static func signature(
        for url: URL,
        fileManager: FileManager
    ) -> CacheSignature? {
        guard (try? ClaudeStatuslineSnapshotReader.validateCacheFile(at: url)) != nil else {
            return nil
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return CacheSignature(
            fileID: uint64Value(attributes[.systemFileNumber]),
            size: uint64Value(attributes[.size]),
            modificationDate: attributes[.modificationDate] as? Date
        )
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            return number.uint64Value
        case let value as UInt64:
            return value
        case let value as UInt:
            return UInt64(value)
        case let value as Int where value >= 0:
            return UInt64(value)
        default:
            return nil
        }
    }
}

final class ClaudeStatusCachePoller {
    private let tracker: ClaudeStatusCacheChangeTracker
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    init(
        tracker: ClaudeStatusCacheChangeTracker = ClaudeStatusCacheChangeTracker(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.promptjuice.claude-status-cache-poller",
            qos: .utility
        )
    ) {
        self.tracker = tracker
        self.queue = queue
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [tracker] in
            guard tracker.consumeChange() else {
                return
            }

            Task { @MainActor in
                onChange()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
