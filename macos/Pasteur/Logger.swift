import Foundation

enum Logger {
    static var enabled = false

    static func log(_ message: String) {
        guard enabled else { return }
        print(message)
    }
}
