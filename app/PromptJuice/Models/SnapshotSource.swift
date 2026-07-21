enum SnapshotSource: String, Equatable, Sendable {
    case fixture
    case codexStub
    case codexAppServer
    case codexCache
    case claudeStatusline
    case claudeUsageCLI
    case claudeLocalLogs
    case claudeCache
}
