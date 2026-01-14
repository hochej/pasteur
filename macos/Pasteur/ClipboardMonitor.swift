import AppKit

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let pollIntervalMs: Int
    private let handler: (String) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastText: String?
    private var lastEmitAt: Date?
    private let minimumIntervalMs: Int

    init(pollIntervalMs: Int, minimumIntervalMs: Int = 300, handler: @escaping (String) -> Void) {
        self.pollIntervalMs = max(100, pollIntervalMs)
        self.minimumIntervalMs = max(0, minimumIntervalMs)
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
        if let lastEmitAt, minimumIntervalMs > 0 {
            let elapsedMs = Int(Date().timeIntervalSince(lastEmitAt) * 1000)
            if elapsedMs < minimumIntervalMs {
                return
            }
        }
        lastText = text
        lastEmitAt = Date()
        handler(text)
    }
}
