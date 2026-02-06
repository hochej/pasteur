import AppKit
import Foundation

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let pollIntervalMs: Int
    private let handler: (String) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastText: String?
    private var lastEmitAt: Date?
    private let minimumIntervalMs: Int

    /// If the clipboard changes but the text is identical, we still want to emit occasionally
    /// (users often re-copy the same molecule while testing).
    private let duplicateSuppressMs: Int

    init(
        pollIntervalMs: Int,
        minimumIntervalMs: Int = 300,
        duplicateSuppressMs: Int = 1500,
        handler: @escaping (String) -> Void
    ) {
        self.pollIntervalMs = max(100, pollIntervalMs)
        self.minimumIntervalMs = max(0, minimumIntervalMs)
        self.duplicateSuppressMs = max(0, duplicateSuppressMs)
        self.handler = handler
        self.lastChangeCount = pasteboard.changeCount

        // Don't seed lastText with current clipboard content. Otherwise, if the user copies the
        // same text that was already on the clipboard at launch, we would never emit.
        self.lastText = nil
    }

    func start() {
        stop()
        Logger.log("[Pasteur] Clipboard monitor started poll=\(pollIntervalMs)ms")

        // Use a timer attached to the main run loop in .common modes so it continues
        // firing while the user is interacting with menus/panels.
        let t = Timer(timeInterval: TimeInterval(pollIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
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

        let now = Date()
        let elapsedMs: Int
        if let lastEmitAt {
            elapsedMs = Int(now.timeIntervalSince(lastEmitAt) * 1000)
        } else {
            elapsedMs = Int.max
        }

        if minimumIntervalMs > 0, elapsedMs < minimumIntervalMs {
            return
        }

        if let lastText, text == lastText, duplicateSuppressMs > 0, elapsedMs < duplicateSuppressMs {
            // Some apps bump changeCount more than once for the same content.
            return
        }

        lastText = text
        lastEmitAt = now
        Logger.log("[Pasteur] Clipboard monitor match (chars=\(text.count))")
        handler(text)
    }
}
