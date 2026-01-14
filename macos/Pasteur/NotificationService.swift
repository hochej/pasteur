import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private let center: UNUserNotificationCenter?
    private var authorized = false

    private init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            center = UNUserNotificationCenter.current()
        } else {
            center = nil
            Logger.log("[Pasteur] Notifications disabled (no app bundle).")
        }
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func send(message: String) {
        guard let center else {
            Logger.log("[Pasteur] Notification dropped (no app bundle): \(message)")
            return
        }
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
