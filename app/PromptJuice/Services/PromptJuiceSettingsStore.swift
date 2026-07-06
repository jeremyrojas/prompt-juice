import Foundation

@MainActor
final class PromptJuiceSettingsStore {
    static let shared = PromptJuiceSettingsStore()

    private enum Key {
        static let enabledProviders = "enabledProviders"
        static let remainingMinutesThreshold = "remainingMinutesThreshold"
        static let remainingPercentThreshold = "remainingPercentThreshold"
        static let notifiedUseSoonWindowIDs = "notifiedUseSoonWindowIDs"
        static let useSoonNotificationsEnabled = "useSoonNotificationsEnabled"
        static let usageSourceMode = "usageSourceMode"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var thresholds: AlertThresholds {
        AlertThresholds(
            remainingMinutes: defaults.integer(forKey: Key.remainingMinutesThreshold),
            remainingPercent: defaults.integer(forKey: Key.remainingPercentThreshold)
        )
    }

    var enabledProviders: Set<UsageProvider> {
        get {
            guard let rawValues = defaults.stringArray(forKey: Key.enabledProviders) else {
                return Set(UsageProvider.allCases)
            }

            let providers = Set(rawValues.compactMap(UsageProvider.init(rawValue:)))
            return providers.isEmpty ? Set(UsageProvider.allCases) : providers
        }
        set {
            guard !newValue.isEmpty else {
                return
            }

            let rawValues = UsageProvider.allCases
                .filter { newValue.contains($0) }
                .map(\.rawValue)
            defaults.set(rawValues, forKey: Key.enabledProviders)
        }
    }

    var isFirstRun: Bool {
        defaults.object(forKey: Key.enabledProviders) == nil
    }

    var useSoonNotificationsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.useSoonNotificationsEnabled) != nil else {
                return true
            }

            return defaults.bool(forKey: Key.useSoonNotificationsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.useSoonNotificationsEnabled)
        }
    }

    var notifiedUseSoonWindowIDs: [String: String] {
        get {
            defaults.dictionary(forKey: Key.notifiedUseSoonWindowIDs) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Key.notifiedUseSoonWindowIDs)
        }
    }

    func markUseSoonWindowNotified(provider: UsageProvider, windowID: String) {
        var next = notifiedUseSoonWindowIDs
        next[provider.rawValue] = windowID
        notifiedUseSoonWindowIDs = next
    }

    func clearUseSoonWindowNotification(provider: UsageProvider) {
        var next = notifiedUseSoonWindowIDs
        next.removeValue(forKey: provider.rawValue)
        notifiedUseSoonWindowIDs = next
    }

    var usageSourceMode: UsageSourceMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.usageSourceMode),
                  let mode = UsageSourceMode(rawValue: rawValue) else {
                return UsageSourceMode.defaultMode
            }

            if mode.isUserFacing {
                return mode
            }

            return UsageSourceMode.defaultMode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.usageSourceMode)
        }
    }

    func saveThresholds(_ thresholds: AlertThresholds) {
        defaults.set(thresholds.remainingMinutes, forKey: Key.remainingMinutesThreshold)
        defaults.set(thresholds.remainingPercent, forKey: Key.remainingPercentThreshold)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.remainingMinutesThreshold: AlertThresholds.default.remainingMinutes,
            Key.remainingPercentThreshold: AlertThresholds.default.remainingPercent,
            Key.usageSourceMode: UsageSourceMode.defaultMode.rawValue
        ])
    }
}
