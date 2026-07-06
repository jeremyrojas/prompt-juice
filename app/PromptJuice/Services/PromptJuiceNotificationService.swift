import Foundation
import UserNotifications

@MainActor
final class PromptJuiceNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onUseSoonNotificationActivated: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        Task { [center] in
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            completion?(granted)
        }
    }

    func sendUseSoonNotification(
        _ notice: UseSoonNotice,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        requestAuthorization { [weak self] granted in
            guard granted else {
                completion?(false)
                return
            }

            self?.deliverUseSoonNotification(notice, completion: completion)
        }
    }

    func removeUseSoonNotifications(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func deliverUseSoonNotification(
        _ notice: UseSoonNotice,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notice.notificationIdentifier,
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
}
