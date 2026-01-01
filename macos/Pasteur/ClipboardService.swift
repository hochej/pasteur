import AppKit

final class ClipboardService {
    private let pasteboard = NSPasteboard.general

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
