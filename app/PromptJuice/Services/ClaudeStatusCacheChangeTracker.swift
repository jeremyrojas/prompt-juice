import Darwin
import Foundation

final class ClaudeStatusCacheChangeTracker {
    private struct CacheSignature: Equatable {
        let fileID: UInt64?
        let size: UInt64?
        let modificationDate: Date?
    }

    let cacheURL: URL
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
    private static let queueKey = DispatchSpecificKey<Bool>()

    private let tracker: ClaudeStatusCacheChangeTracker
    private let queue: DispatchQueue
    private let usesDirectoryWatcher: Bool
    private var timer: DispatchSourceTimer?
    private var directorySource: DispatchSourceFileSystemObject?

    init(
        cacheURL: URL = ClaudeStatuslineSnapshotReader.defaultCacheURL(),
        tracker: ClaudeStatusCacheChangeTracker? = nil,
        usesDirectoryWatcher: Bool = true,
        queue: DispatchQueue = DispatchQueue(
            label: "com.promptjuice.claude-status-cache-poller",
            qos: .utility
        )
    ) {
        self.tracker = tracker ?? ClaudeStatusCacheChangeTracker(cacheURL: cacheURL)
        self.queue = queue
        self.usesDirectoryWatcher = usesDirectoryWatcher
        self.queue.setSpecific(key: Self.queueKey, value: true)
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        tracker.reset()
        if usesDirectoryWatcher {
            startDirectoryWatcher(onChange: onChange)
        }
        startTimer(onChange: onChange)
    }

    func reset() {
        tracker.reset()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        directorySource?.cancel()
        directorySource = nil
        drainQueue()
    }

    private func startTimer(onChange: @escaping @MainActor () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.consumeChange(source: "poller", onChange: onChange)
        }
        self.timer = timer
        timer.resume()
    }

    private func startDirectoryWatcher(onChange: @escaping @MainActor () -> Void) {
        let directoryURL = tracker.cacheURL.deletingLastPathComponent()
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            PromptJuiceLog.usage.notice("Claude status cache directory watcher unavailable")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.consumeChange(source: "directory watcher", onChange: onChange)
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        directorySource = source
        source.resume()
        PromptJuiceLog.usage.notice("Claude status cache directory watcher started")
    }

    private func consumeChange(
        source: String,
        onChange: @escaping @MainActor () -> Void
    ) {
        guard tracker.consumeChange() else {
            return
        }

        PromptJuiceLog.usage.notice("Claude status cache change detected via \(source, privacy: .public)")
        Task { @MainActor in
            onChange()
        }
    }

    private func drainQueue() {
        if DispatchQueue.getSpecific(key: Self.queueKey) == nil {
            queue.sync {}
        }
    }
}
