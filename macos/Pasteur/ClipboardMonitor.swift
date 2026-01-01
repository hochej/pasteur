import AppKit

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let pollIntervalMs: Int
    private let handler: (String) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastText: String?

    init(pollIntervalMs: Int, handler: @escaping (String) -> Void) {
        self.pollIntervalMs = max(100, pollIntervalMs)
        self.handler = handler
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(pollIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        if text == lastText { return }
        lastText = text
        handler(text)
    }
}
