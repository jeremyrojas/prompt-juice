import Foundation
import UserNotifications

enum PromptJuiceNotificationAuthorization: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied

    var allowsDelivery: Bool {
        self == .authorized
    }
}

@MainActor
final class PromptJuiceNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onUseSoonNotificationActivated: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func refreshAuthorizationStatus(
        completion: @MainActor @Sendable @escaping (PromptJuiceNotificationAuthorization) -> Void
    ) {
        Task { [center] in
            let settings = await center.notificationSettings()
            let authorization = Self.authorization(from: settings.authorizationStatus)

            await MainActor.run {
                completion(authorization)
            }
        }
    }

    func requestAuthorization(
        completion: (@MainActor @Sendable (PromptJuiceNotificationAuthorization) -> Void)? = nil
    ) {
        Task { [center] in
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let settings = await center.notificationSettings()
            let authorization = Self.authorization(from: settings.authorizationStatus)

            await MainActor.run {
                completion?(authorization)
            }
        }
    }

    func sendUseSoonNotification(
        _ notification: MergedUseSoonNotification,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        requestAuthorization { [weak self] authorization in
            guard authorization.allowsDelivery else {
                completion?(false)
                return
            }

            self?.deliverUseSoonNotification(notification, completion: completion)
        }
    }

    func removeUseSoonNotifications(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func deliverUseSoonNotification(
        _ notification: MergedUseSoonNotification,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            Task { @MainActor in
                completion?(error == nil)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier

        if identifier.hasPrefix("promptjuice.use-soon.") {
            Task { @MainActor [weak self] in
                self?.onUseSoonNotificationActivated?()
            }
        }

        completionHandler()
    }

    private static func authorization(
        from status: UNAuthorizationStatus
    ) -> PromptJuiceNotificationAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}
