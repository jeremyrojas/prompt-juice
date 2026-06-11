import Foundation
import UserNotifications

@MainActor
final class PromptJuiceNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

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

    func sendUseSoonNotification(title: String, body: String) {
        requestAuthorization { [weak self] granted in
            guard granted else {
                return
            }

            self?.deliverUseSoonNotification(title: title, body: body)
        }
    }

    private func deliverUseSoonNotification(title: String, body: String) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "promptjuice.demo.use-soon.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
