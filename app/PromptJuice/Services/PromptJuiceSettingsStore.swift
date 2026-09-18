import CoreGraphics
import Foundation

@MainActor
final class PromptJuiceSettingsStore {
    static let shared = PromptJuiceSettingsStore()

    private enum Key {
        static let enabledProviders = "enabledProviders"
        static let expandedProviders = "expandedProviders"
        static let remainingMinutesThreshold = "remainingMinutesThreshold"
        static let remainingPercentThreshold = "remainingPercentThreshold"
        static let fiveHourMinutes = "fiveHourRemainingMinutesThreshold"
        static let fiveHourPercent = "fiveHourRemainingPercentThreshold"
        static let weeklyMinutes = "weeklyRemainingMinutesThreshold"
        static let weeklyPercent = "weeklyRemainingPercentThreshold"
        static let notifiedUseSoonWindowIDs = "notifiedUseSoonWindowIDs"
        static let useSoonNotificationsEnabled = "useSoonNotificationsEnabled"
        static let didOfferUseSoonNotification = "didOfferUseSoonNotification"
        static let lastUseSoonNotificationIdentifier = "lastUseSoonNotificationIdentifier"
        static let usageSourceMode = "usageSourceMode"
        static let pinnedJuicebarOriginX = "pinnedJuicebarOriginX"
        static let pinnedJuicebarOriginY = "pinnedJuicebarOriginY"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyThresholds()
        registerDefaults()
    }

    func sharedThresholds(for cadence: LimitCadence) -> AlertThresholds {
        let keys = sharedThresholdKeys(for: cadence)
        return AlertThresholds(
            remainingMinutes: defaults.integer(forKey: keys.minutes),
            remainingPercent: defaults.integer(forKey: keys.percent)
        )
    }

    func thresholds(for provider: UsageProvider, cadence: LimitCadence) -> AlertThresholds {
        let prefix = "thresholds.\(provider.rawValue).\(cadence.rawValue)"
        let minutesKey = "\(prefix).minutes"
        let percentKey = "\(prefix).percent"
        guard defaults.object(forKey: minutesKey) != nil,
              defaults.object(forKey: percentKey) != nil else {
            return sharedThresholds(for: cadence)
        }
        return AlertThresholds(
            remainingMinutes: defaults.integer(forKey: minutesKey),
            remainingPercent: defaults.integer(forKey: percentKey)
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

    var expandedProviders: Set<UsageProvider> {
        get {
            Set((defaults.stringArray(forKey: Key.expandedProviders) ?? [])
                .compactMap(UsageProvider.init(rawValue:)))
        }
        set {
            defaults.set(
                UsageProvider.allCases.filter { newValue.contains($0) }.map(\.rawValue),
                forKey: Key.expandedProviders
            )
        }
    }

    var isFirstRun: Bool {
        defaults.object(forKey: Key.enabledProviders) == nil
    }

    var useSoonNotificationsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.useSoonNotificationsEnabled) != nil else {
                return false
            }

            return defaults.bool(forKey: Key.useSoonNotificationsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.useSoonNotificationsEnabled)
        }
    }

    /// True once the in-panel "want notifications?" prime has been shown and
    /// answered (enabled or dismissed). Latches forever so the just-in-time ask
    /// appears at most once; Settings stays the always-on path afterward.
    var didOfferUseSoonNotification: Bool {
        get {
            defaults.bool(forKey: Key.didOfferUseSoonNotification)
        }
        set {
            defaults.set(newValue, forKey: Key.didOfferUseSoonNotification)
        }
    }

    /// Identifier of the most recently delivered use-soon notification. Because
    /// several orange providers are merged into a single banner, this is the one
    /// id to remove when the covered windows go stale.
    var lastUseSoonNotificationIdentifier: String? {
        get {
            defaults.string(forKey: Key.lastUseSoonNotificationIdentifier)
        }
        set {
            defaults.set(newValue, forKey: Key.lastUseSoonNotificationIdentifier)
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

    func markUseSoonWindowNotified(latchKey: String, windowID: String) {
        var next = notifiedUseSoonWindowIDs
        next[latchKey] = windowID
        notifiedUseSoonWindowIDs = next
    }

    func clearUseSoonWindowNotification(latchKey: String) {
        var next = notifiedUseSoonWindowIDs
        next.removeValue(forKey: latchKey)
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

    var pinnedJuicebarOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.pinnedJuicebarOriginX) != nil,
                  defaults.object(forKey: Key.pinnedJuicebarOriginY) != nil else {
                return nil
            }

            return CGPoint(
                x: defaults.double(forKey: Key.pinnedJuicebarOriginX),
                y: defaults.double(forKey: Key.pinnedJuicebarOriginY)
            )
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.pinnedJuicebarOriginX)
                defaults.removeObject(forKey: Key.pinnedJuicebarOriginY)
                return
            }

            defaults.set(Double(newValue.x), forKey: Key.pinnedJuicebarOriginX)
            defaults.set(Double(newValue.y), forKey: Key.pinnedJuicebarOriginY)
        }
    }

    func saveThresholds(
        _ thresholds: AlertThresholds,
        for cadence: LimitCadence,
        provider: UsageProvider? = nil
    ) {
        let keys: (minutes: String, percent: String)
        if let provider {
            let prefix = "thresholds.\(provider.rawValue).\(cadence.rawValue)"
            keys = ("\(prefix).minutes", "\(prefix).percent")
        } else {
            keys = sharedThresholdKeys(for: cadence)
        }
        defaults.set(thresholds.remainingMinutes, forKey: keys.minutes)
        defaults.set(thresholds.remainingPercent, forKey: keys.percent)
    }

    private func sharedThresholdKeys(for cadence: LimitCadence) -> (minutes: String, percent: String) {
        switch cadence {
        case .fiveHour: (Key.fiveHourMinutes, Key.fiveHourPercent)
        case .weekly: (Key.weeklyMinutes, Key.weeklyPercent)
        }
    }

    private func migrateLegacyThresholds() {
        let newMinutes = defaults.integer(forKey: Key.fiveHourMinutes)
        if defaults.object(forKey: Key.remainingMinutesThreshold) != nil,
           newMinutes == 0 || newMinutes == AlertThresholds.default.remainingMinutes {
            let oldMinutes = defaults.integer(forKey: Key.remainingMinutesThreshold)
            defaults.set(oldMinutes > 0 ? oldMinutes : AlertThresholds.default.remainingMinutes,
                         forKey: Key.fiveHourMinutes)
        }
        let newPercent = defaults.integer(forKey: Key.fiveHourPercent)
        if defaults.object(forKey: Key.remainingPercentThreshold) != nil,
           newPercent == 0 || newPercent == AlertThresholds.default.remainingPercent {
            let oldPercent = defaults.integer(forKey: Key.remainingPercentThreshold)
            defaults.set(oldPercent > 0 ? oldPercent : AlertThresholds.default.remainingPercent,
                         forKey: Key.fiveHourPercent)
        }
        defaults.removeObject(forKey: Key.remainingMinutesThreshold)
        defaults.removeObject(forKey: Key.remainingPercentThreshold)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.fiveHourMinutes: AlertThresholds.default.remainingMinutes,
            Key.fiveHourPercent: AlertThresholds.default.remainingPercent,
            Key.weeklyMinutes: AlertThresholds.weeklyDefault.remainingMinutes,
            Key.weeklyPercent: AlertThresholds.weeklyDefault.remainingPercent,
            Key.useSoonNotificationsEnabled: false,
            Key.usageSourceMode: UsageSourceMode.defaultMode.rawValue
        ])
    }
}
