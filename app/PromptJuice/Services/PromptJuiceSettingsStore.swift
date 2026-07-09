import CoreGraphics
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
        static let didOfferUseSoonNotification = "didOfferUseSoonNotification"
        static let lastUseSoonNotificationIdentifier = "lastUseSoonNotificationIdentifier"
        static let usageSourceMode = "usageSourceMode"
        static let pinnedJuicebarOriginX = "pinnedJuicebarOriginX"
        static let pinnedJuicebarOriginY = "pinnedJuicebarOriginY"
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

    func saveThresholds(_ thresholds: AlertThresholds) {
        defaults.set(thresholds.remainingMinutes, forKey: Key.remainingMinutesThreshold)
        defaults.set(thresholds.remainingPercent, forKey: Key.remainingPercentThreshold)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.remainingMinutesThreshold: AlertThresholds.default.remainingMinutes,
            Key.remainingPercentThreshold: AlertThresholds.default.remainingPercent,
            Key.useSoonNotificationsEnabled: false,
            Key.usageSourceMode: UsageSourceMode.defaultMode.rawValue
        ])
    }
}
