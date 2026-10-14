import Foundation
import UserNotifications

/// Local "flush expected" notifications, at most one per day.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        center.add(UNNotificationRequest(identifier: "flush-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
