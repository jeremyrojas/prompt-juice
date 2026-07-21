enum SnapshotSource: String, Equatable, Sendable {
    case fixture
    case codexStub
    case codexAppServer
    case codexCache
    case claudeUsageCLI
    case claudeLocalLogs
    case claudeCache
}
