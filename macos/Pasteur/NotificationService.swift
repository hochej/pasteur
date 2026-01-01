import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func send(message: String) {
        guard authorized else {
            Logger.log("[Pasteur] Notification dropped (not authorized): \(message)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Pasteur"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
