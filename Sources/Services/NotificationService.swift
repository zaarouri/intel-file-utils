import Foundation
import AppKit
import UserNotifications

public final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationService()

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("[NotificationService] Authorization error: %@", error.localizedDescription)
            }
        }
    }

    public func notify(title: String, message: String, success: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = success ? .default : .defaultCritical

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        // Pass nil for completionHandler to prevent any background callback assertions
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        // Play feedback sound and deliver local notification
        DispatchQueue.main.async {
            if success {
                NSSound(named: "Glass")?.play()
            } else {
                NSSound(named: "Basso")?.play()
            }
        }
    }

    // Display notifications even when the app is active
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
