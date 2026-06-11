import Foundation

@MainActor
final class PromptJuiceSettingsStore {
    static let shared = PromptJuiceSettingsStore()

    private enum Key {
        static let remainingMinutesThreshold = "remainingMinutesThreshold"
        static let remainingPercentThreshold = "remainingPercentThreshold"
        static let snoozedDemoWindowID = "snoozedDemoWindowID"
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

    var snoozedDemoWindowID: String? {
        get {
            defaults.string(forKey: Key.snoozedDemoWindowID)
        }
        set {
            defaults.set(newValue, forKey: Key.snoozedDemoWindowID)
        }
    }

    var usageSourceMode: UsageSourceMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.usageSourceMode),
                  let mode = UsageSourceMode(rawValue: rawValue) else {
                return UsageSourceMode.defaultMode
            }

            return mode
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
