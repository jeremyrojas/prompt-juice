import Foundation

struct ClaudePrerequisiteCheck: Sendable, Equatable {
    let access: ClaudeAccessState
    let location: ClaudeExecutableLocation?
    let version: ClaudeVersionGateResult?
    let authentication: ClaudeAuthentication?
}

protocol ClaudePrerequisiteChecking: Sendable {
    func check(environment: [String: String]) -> ClaudePrerequisiteCheck
}

struct SystemClaudePrerequisiteChecker: ClaudePrerequisiteChecking, @unchecked Sendable {
    let versionProbe: ClaudeVersionProbe
    let authProbe: ClaudeAuthProbe

    init(
        versionProbe: ClaudeVersionProbe = ClaudeVersionProbe(),
        authProbe: ClaudeAuthProbe = ClaudeAuthProbe()
    ) {
        self.versionProbe = versionProbe
        self.authProbe = authProbe
    }

    func check(environment: [String: String]) -> ClaudePrerequisiteCheck {
        guard let location = ClaudeExecutableLocator.locate(environment: environment) else {
            return ClaudePrerequisiteCheck(
                access: .cliMissing,
                location: nil,
                version: nil,
                authentication: nil
            )
        }

        let version = versionProbe.probe(
            executableURL: location.resolvedURL,
            environment: environment
        )
        let authentication = authProbe.probe(
            executableURL: location.resolvedURL,
            environment: environment
        )

        let access: ClaudeAccessState
        switch version {
        case .updateRequired(let installed, let minimum):
            access = .updateRequired(installed: installed, minimum: minimum)
        case .unreadable:
            access = .authCheckFailed
        case .supported:
            access = Self.accessState(for: authentication)
        }

        return ClaudePrerequisiteCheck(
            access: access,
            location: location,
            version: version,
            authentication: authentication
        )
    }

    private static func accessState(for authentication: ClaudeAuthentication) -> ClaudeAccessState {
        switch authentication {
        case .subscription(let plan):
            .subscription(plan: plan)
        case .apiBilling:
            .apiBilling
        case .externalProvider(let provider):
            .externalProvider(provider)
        case .signedOut(let reason):
            .signedOut(reason: reason)
        case .unsupported:
            .unsupportedAuth
        case .checkFailed:
            .authCheckFailed
        }
    }
}

protocol ClaudeUsageProbing: Sendable {
    func probe(
        executableURL: URL,
        version: ClaudeVersionGateResult,
        authentication: ClaudeAuthentication,
        workspaceURL: URL,
        environment: [String: String],
        now: Date,
        calendar: Calendar,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> ClaudeUsageProbeOutcome
}

extension ClaudeUsageProbe: ClaudeUsageProbing {}

protocol ClaudeExactUsageCaching: Sendable {
    func save(_ snapshot: ProviderSnapshot)
    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot?
}

extension ClaudeSnapshotCache: ClaudeExactUsageCaching {}

protocol ClaudeUsageSnapshotProviding: Sendable {
    func snapshot(
        now: Date,
        reason: ClaudeRefreshReason,
        force: Bool,
        providerEnabled: Bool,
        isAwake: Bool,
        isOnline: Bool
    ) async -> ClaudeUsageCoordinatorState
}

struct ClaudeUsagePersistenceMetadata: Sendable, Equatable {
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let nextAttemptAt: Date?
    let recentAttempts: [ClaudeUsageAttempt]
    let authenticationFingerprint: String?
    let wasRepaired: Bool
}

final class ClaudeUsagePersistence: @unchecked Sendable {
    private static let schemaVersion = 1
    private static let backoffMinutes = [5, 15, 30, 60]

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = "claudeUsageCoordinatorState"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func metadata(now: Date) -> ClaudeUsagePersistenceMetadata {
        lock.lock()
        defer { lock.unlock() }

        let loaded = loadRecord()
        var record = loaded.record
        let attempts = record.recentAttempts.filter {
            now.timeIntervalSince($0.date) >= 0
                && now.timeIntervalSince($0.date) < 60 * 60
        }
        var changed = attempts != record.recentAttempts
        record.recentAttempts = attempts

        if let nextAttemptAt = record.nextAttemptAt,
           nextAttemptAt <= now {
            record.nextAttemptAt = nil
            changed = true
        }
        if changed {
            saveRecord(record)
        }

        return ClaudeUsagePersistenceMetadata(
            lastAttemptAt: record.lastAttemptAt,
            lastSuccessAt: record.lastSuccessAt,
            nextAttemptAt: record.nextAttemptAt,
            recentAttempts: record.recentAttempts,
            authenticationFingerprint: record.authenticationFingerprint,
            wasRepaired: loaded.wasRepaired
        )
    }

    func authenticationFingerprint() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loadRecord().record.authenticationFingerprint
    }

    func recordAttempt(at date: Date, reason: ClaudeRefreshReason) {
        mutate { record in
            record.lastAttemptAt = date
            record.recentAttempts = record.recentAttempts.filter {
                date.timeIntervalSince($0.date) >= 0
                    && date.timeIntervalSince($0.date) < 60 * 60
            }
            record.recentAttempts.append(ClaudeUsageAttempt(date: date, reason: reason))
            record.recentAttempts = Array(record.recentAttempts.suffix(12))
        }
    }

    func recordSuccess(at date: Date) {
        mutate { record in
            record.lastSuccessAt = date
            record.nextBackoffIndex = 0
            record.nextAttemptAt = nil
        }
    }

    func advanceBackoff(from date: Date) -> Date {
        lock.lock()
        defer { lock.unlock() }

        var record = loadRecord().record
        let index = min(max(0, record.nextBackoffIndex), Self.backoffMinutes.count - 1)
        let nextAttemptAt = date.addingTimeInterval(
            TimeInterval(Self.backoffMinutes[index] * 60)
        )
        record.nextBackoffIndex = min(index + 1, Self.backoffMinutes.count - 1)
        record.nextAttemptAt = nextAttemptAt
        saveRecord(record)
        return nextAttemptAt
    }

    func updateAuthenticationFingerprint(_ fingerprint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var record = loadRecord().record
        let changed = record.authenticationFingerprint != nil
            && record.authenticationFingerprint != fingerprint
        record.authenticationFingerprint = fingerprint
        if changed {
            record.nextBackoffIndex = 0
            record.nextAttemptAt = nil
        }
        saveRecord(record)
        return changed
    }

    func resetBackoff() {
        mutate { record in
            record.nextBackoffIndex = 0
            record.nextAttemptAt = nil
        }
    }

    private func mutate(_ body: (inout Record) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var record = loadRecord().record
        body(&record)
        saveRecord(record)
    }

    private func loadRecord() -> (record: Record, wasRepaired: Bool) {
        guard let data = defaults.data(forKey: key) else {
            return (Record(), false)
        }
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == Self.schemaVersion,
              (0..<Self.backoffMinutes.count).contains(record.nextBackoffIndex),
              Self.isValid(record.lastAttemptAt),
              Self.isValid(record.lastSuccessAt),
              Self.isValid(record.nextAttemptAt),
              record.recentAttempts.allSatisfy({ Self.isValid($0.date) }) else {
            defaults.removeObject(forKey: key)
            return (Record(), true)
        }
        return (record, false)
    }

    private func saveRecord(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func isValid(_ date: Date?) -> Bool {
        date?.timeIntervalSinceReferenceDate.isFinite ?? true
    }

    private struct Record: Codable, Equatable {
        var schemaVersion = ClaudeUsagePersistence.schemaVersion
        var lastAttemptAt: Date?
        var lastSuccessAt: Date?
        var nextBackoffIndex = 0
        var nextAttemptAt: Date?
        var recentAttempts: [ClaudeUsageAttempt] = []
        var authenticationFingerprint: String?
    }
}

struct ClaudeExactSourceLadder {
    static func resolve(
        primary: ProviderSnapshot?,
        cache: any ClaudeExactUsageCaching,
        estimateReader: any ClaudeLocalUsageReading,
        now: Date
    ) -> ProviderSnapshot? {
        if let primary, isUsable(primary, now: now) {
            return primary
        }

        if let cached = cache.snapshot(now: now, failureDetail: nil),
           isUsable(cached, now: now) {
            return cached
        }

        if let estimate = try? estimateReader.snapshot(now: now),
           estimate.confidence == .estimated,
           isUsable(estimate, now: now) {
            return estimate
        }

        return nil
    }

    private static func isUsable(_ snapshot: ProviderSnapshot, now: Date) -> Bool {
        snapshot.identity == .claude
            && snapshot.isAvailable
            && !snapshot.isExpired(at: now)
            && !snapshot.isFreshSessionWindow
    }
}

actor ClaudeUsageCoordinator: ClaudeUsageSnapshotProviding {
    private struct Execution: Sendable {
        let prerequisites: ClaudePrerequisiteCheck
        let probeOutcome: ClaudeUsageProbeOutcome?
    }

    private let prerequisiteChecker: any ClaudePrerequisiteChecking
    private let usageProbe: any ClaudeUsageProbing
    private let workspace: ClaudeProbeWorkspace
    private let cache: any ClaudeExactUsageCaching
    private let estimateReader: any ClaudeLocalUsageReading
    private let persistence: ClaudeUsagePersistence
    private let schedule: ClaudeUsageSchedule
    private let environment: [String: String]
    private let calendar: Calendar
    private let featureEnabled: Bool

    private var state: ClaudeUsageCoordinatorState
    private var inFlight: (id: UUID, task: Task<Execution, Never>)?
    private var appliedExecutionID: UUID?

    init(
        prerequisiteChecker: any ClaudePrerequisiteChecking = SystemClaudePrerequisiteChecker(),
        usageProbe: any ClaudeUsageProbing = ClaudeUsageProbe(),
        workspace: ClaudeProbeWorkspace = ClaudeProbeWorkspace(),
        cache: any ClaudeExactUsageCaching = ClaudeSnapshotCache.shared,
        estimateReader: any ClaudeLocalUsageReading = ClaudeLocalLogUsageReader(),
        persistence: ClaudeUsagePersistence = ClaudeUsagePersistence(),
        schedule: ClaudeUsageSchedule = ClaudeUsageSchedule(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendar: Calendar = Calendar(identifier: .gregorian),
        featureEnabled: Bool = true
    ) {
        self.prerequisiteChecker = prerequisiteChecker
        self.usageProbe = usageProbe
        self.workspace = workspace
        self.cache = cache
        self.estimateReader = estimateReader
        self.persistence = persistence
        self.schedule = schedule
        self.environment = environment
        self.calendar = calendar
        self.featureEnabled = featureEnabled
        state = ClaudeUsageCoordinatorState(
            access: persistence.authenticationFingerprint().flatMap {
                ClaudeAccessState(persistenceFingerprint: $0)
            } ?? .checking,
            refresh: .idle,
            snapshot: cache.snapshot(now: Date(), failureDetail: nil)
        )
    }

    func currentState() -> ClaudeUsageCoordinatorState {
        state
    }

    func snapshot(
        now: Date,
        reason: ClaudeRefreshReason,
        force: Bool = false,
        providerEnabled: Bool = true,
        isAwake: Bool = true,
        isOnline: Bool = true
    ) async -> ClaudeUsageCoordinatorState {
        if let inFlight {
            let execution = await inFlight.task.value
            applyIfNeeded(execution, id: inFlight.id, now: now)
            return state
        }

        guard featureEnabled else {
            state = ClaudeUsageCoordinatorState(
                access: state.access,
                refresh: .idle,
                snapshot: fallbackSnapshot(primary: nil, now: now)
            )
            return state
        }

        let metadata = persistence.metadata(now: now)
        let decision = schedule.decision(
            for: ClaudeUsageScheduleContext(
                now: now,
                reason: reason,
                force: force,
                providerEnabled: providerEnabled,
                isAwake: isAwake,
                isOnline: isOnline,
                lastAttemptAt: metadata.lastAttemptAt,
                lastSuccessAt: metadata.lastSuccessAt,
                nextAttemptAt: metadata.nextAttemptAt,
                recentAttempts: metadata.recentAttempts
            )
        )

        guard decision == .probe else {
            state = stateForSkippedDecision(decision, now: now)
            return state
        }

        let workspaceURL: URL
        do {
            workspaceURL = try workspace.prepare()
        } catch {
            state = ClaudeUsageCoordinatorState(
                access: state.access,
                refresh: .failed(.workspace),
                snapshot: fallbackSnapshot(primary: nil, now: now)
            )
            return state
        }

        persistence.recordAttempt(at: now, reason: reason)
        state = ClaudeUsageCoordinatorState(
            access: state.access,
            refresh: .refreshing,
            snapshot: state.snapshot
        )

        let prerequisiteChecker = prerequisiteChecker
        let usageProbe = usageProbe
        let environment = environment
        let calendar = calendar
        let executionID = UUID()
        let task = Task.detached(priority: .utility) {
            let prerequisites = prerequisiteChecker.check(environment: environment)
            guard case .subscription = prerequisites.access,
                  let executableURL = prerequisites.location?.resolvedURL,
                  let version = prerequisites.version,
                  let authentication = prerequisites.authentication else {
                return Execution(prerequisites: prerequisites, probeOutcome: nil)
            }

            let outcome = usageProbe.probe(
                executableURL: executableURL,
                version: version,
                authentication: authentication,
                workspaceURL: workspaceURL,
                environment: environment,
                now: now,
                calendar: calendar,
                isCancelled: {
                    withUnsafeCurrentTask { $0?.isCancelled ?? false }
                }
            )
            return Execution(prerequisites: prerequisites, probeOutcome: outcome)
        }
        inFlight = (executionID, task)

        let execution = await task.value
        applyIfNeeded(execution, id: executionID, now: now)
        return state
    }

    private func applyIfNeeded(_ execution: Execution, id: UUID, now: Date) {
        guard appliedExecutionID != id else {
            return
        }
        appliedExecutionID = id
        if inFlight?.id == id {
            inFlight = nil
        }

        let accessChanged = persistence.updateAuthenticationFingerprint(
            execution.prerequisites.access.persistenceFingerprint
        )
        if accessChanged {
            persistence.resetBackoff()
        }

        guard let probeOutcome = execution.probeOutcome else {
            state = ClaudeUsageCoordinatorState(
                access: execution.prerequisites.access,
                refresh: .idle,
                snapshot: fallbackSnapshot(primary: nil, now: now)
            )
            return
        }

        applyProbeOutcome(
            probeOutcome,
            prerequisiteAccess: execution.prerequisites.access,
            now: now
        )
    }

    private func applyProbeOutcome(
        _ outcome: ClaudeUsageProbeOutcome,
        prerequisiteAccess: ClaudeAccessState,
        now: Date
    ) {
        switch outcome {
        case .parsed(let result):
            let parsedSnapshot = result.reading.map(Self.snapshot(from:))
            if let parsedSnapshot {
                cache.save(parsedSnapshot)
            }

            let snapshot = fallbackSnapshot(primary: parsedSnapshot, now: now)
            let access = Self.planConfirmedAccess(
                prerequisiteAccess,
                reading: result.reading
            )
            if result.rateLimitObserved {
                let nextAttemptAt = persistence.advanceBackoff(from: now)
                state = ClaudeUsageCoordinatorState(
                    access: access,
                    refresh: .backingOff(nextAttemptAt: nextAttemptAt),
                    snapshot: snapshot
                )
            } else if result.failure != nil || parsedSnapshot == nil {
                state = ClaudeUsageCoordinatorState(
                    access: access,
                    refresh: .failed(.parse),
                    snapshot: snapshot
                )
            } else {
                persistence.recordSuccess(at: now)
                state = ClaudeUsageCoordinatorState(
                    access: access,
                    refresh: .idle,
                    snapshot: snapshot
                )
            }
        case .workspaceTrustRequired:
            state = ClaudeUsageCoordinatorState(
                access: .workspaceTrustRequired,
                refresh: .idle,
                snapshot: fallbackSnapshot(primary: nil, now: now)
            )
        case .timedOut:
            setFailure(.timeout, access: prerequisiteAccess, now: now)
        case .cancelled:
            setFailure(.cancelled, access: prerequisiteAccess, now: now)
        case .outputTooLarge:
            setFailure(.outputTooLarge, access: prerequisiteAccess, now: now)
        case .launchFailed, .processFailed, .startupOnly:
            setFailure(.process, access: prerequisiteAccess, now: now)
        case .ineligible(let reason):
            let access: ClaudeAccessState = switch reason {
            case .unsupportedVersion:
                prerequisiteAccess
            case .authentication:
                .unsupportedAuth
            }
            setFailure(.process, access: access, now: now)
        }
    }

    private func setFailure(
        _ failure: ClaudeProbeFailure,
        access: ClaudeAccessState,
        now: Date
    ) {
        state = ClaudeUsageCoordinatorState(
            access: access,
            refresh: .failed(failure),
            snapshot: fallbackSnapshot(primary: nil, now: now)
        )
    }

    private func stateForSkippedDecision(
        _ decision: ClaudeUsageScheduleDecision,
        now: Date
    ) -> ClaudeUsageCoordinatorState {
        let refresh: ClaudeRefreshState
        switch decision {
        case .skipCooldown(let nextAttemptAt):
            refresh = .backingOff(nextAttemptAt: nextAttemptAt)
        case .skipOffline:
            refresh = .failed(.offline)
        case .skipDisabled, .skipSleeping, .skipDebounce, .skipFresh, .skipBudget, .probe:
            refresh = .idle
        }

        return ClaudeUsageCoordinatorState(
            access: state.access,
            refresh: refresh,
            snapshot: fallbackSnapshot(primary: state.snapshot, now: now)
        )
    }

    private func fallbackSnapshot(primary: ProviderSnapshot?, now: Date) -> ProviderSnapshot? {
        ClaudeExactSourceLadder.resolve(
            primary: primary,
            cache: cache,
            estimateReader: estimateReader,
            now: now
        )
    }

    private static func snapshot(from reading: ClaudeUsageReading) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: reading.session.usedPercent,
                resetAt: reading.session.resetAt,
                durationMinutes: 5 * 60
            ),
            weeklyWindow: reading.weekly.map {
                .available(
                    usedPercent: $0.usedPercent,
                    resetAt: $0.resetAt,
                    durationMinutes: 7 * 24 * 60
                )
            },
            source: .claudeUsageCLI,
            confidence: reading.isSavedReading ? .stale : .exact,
            updatedAt: reading.measuredAt,
            weeklyUpdatedAt: reading.weekly == nil ? nil : reading.measuredAt,
            isFreshSessionWindow: false,
            isFreshWeeklyWindow: false
        )
    }

    private static func planConfirmedAccess(
        _ access: ClaudeAccessState,
        reading: ClaudeUsageReading?
    ) -> ClaudeAccessState {
        guard case .subscription(let authPlan) = access else {
            return access
        }
        return .subscription(plan: reading?.plan ?? authPlan)
    }
}
