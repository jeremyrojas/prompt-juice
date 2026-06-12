import Foundation

@MainActor
final class PromptJuiceSettingsStore {
    static let shared = PromptJuiceSettingsStore()

    private enum Key {
        static let enabledProviders = "enabledProviders"
        static let remainingMinutesThreshold = "remainingMinutesThreshold"
        static let remainingPercentThreshold = "remainingPercentThreshold"
        static let snoozedUsageWindowID = "snoozedUsageWindowID"
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

    var snoozedUsageWindowID: String? {
        get {
            defaults.string(forKey: Key.snoozedUsageWindowID)
        }
        set {
            defaults.set(newValue, forKey: Key.snoozedUsageWindowID)
        }
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
