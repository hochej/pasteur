import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboardService = ClipboardService()
    private let formatDetector = FormatDetector()
    private let configService = ConfigService()
    private var statusItemController: StatusItemController?
    private var hotkeyController: HotkeyController?
    private var viewerPanelController: ViewerPanelController?
    private var appConfig: ConfigService.AppConfig?
    private var clipboardMonitor: ClipboardMonitor?
    private var preferencesController: PreferencesController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("[Pasteur] Application did finish launching.")
        NSApp.setActivationPolicy(.accessory)

        let config = configService.loadConfig()
        appConfig = config
        Logger.enabled = config.debugLogging
        NotificationService.shared.requestAuthorization()

        statusItemController = StatusItemController(
            target: self,
            visualizeAction: #selector(handleVisualizeClipboard),
            preferencesAction: #selector(handlePreferences),
            quitAction: #selector(handleQuit)
        )
        Logger.log("[Pasteur] Status item configured.")

        DispatchQueue.main.async { [weak self] in
            Logger.log("[Pasteur] Preloading viewer panel.")
            let controller = ViewerPanelController()
            self?.viewerPanelController = controller
            controller.applyUIConfig(config.ui)
            controller.applyPopoverConfig(config.popover)
            controller.applyScreenshotDirectory(config.screenshotDirectory)
            controller.applyScreenshotReveal(config.screenshotReveal)
            controller.setAnchorButton(self?.statusItemController?.button)
            Logger.log("[Pasteur] Viewer panel ready.")

            let clipboardConfig = config.clipboardMonitor
            if clipboardConfig.enabled {
                Logger.log("[Pasteur] Clipboard monitor enabled poll=\(clipboardConfig.pollIntervalMs)ms autoShow=\(clipboardConfig.autoShow)")
                let monitor = ClipboardMonitor(pollIntervalMs: clipboardConfig.pollIntervalMs) { [weak self] text in
                    guard let self else { return }
                    if text.utf8.count > 5_000_000 {
                        Logger.log("[Pasteur] Clipboard skipped (>5MB).")
                        return
                    }
                    guard let format = self.formatDetector.detectFormat(for: text) else { return }
                    Logger.log("[Pasteur] Clipboard match format=\(format) bytes=\(text.utf8.count)")
                    DispatchQueue.main.async {
                        if clipboardConfig.autoShow {
                            self.viewerPanelController?.show()
                            self.viewerPanelController?.load(format: format, data: text)
                        }
                    }
                }
                self?.clipboardMonitor = monitor
                monitor.start()
            }
        }

        if config.clipboardMonitor.enabled, let text = clipboardService.readString() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let format = formatDetector.detectFormat(for: trimmed), config.clipboardMonitor.autoShow {
                DispatchQueue.main.async { [weak self] in
                    self?.viewerPanelController?.show()
                    self?.viewerPanelController?.load(format: format, data: text)
                }
            }
        }

        configureHotkey(using: config.hotkey)
    }

    @objc private func handleVisualizeClipboard() {
        guard let rawText = clipboardService.readString(),
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast(message: "Clipboard is empty.")
            return
        }

        if rawText.utf8.count > 5_000_000 {
            showToast(message: "Clipboard content is too large to render.")
            return
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let format = formatDetector.detectFormat(for: trimmed) else {
            showToast(message: "Clipboard doesn't look like a supported molecule format.")
            return
        }

        let payload = format == "xyz" ? normalizeXYZ(rawText) : rawText

        viewerPanelController?.show()
        viewerPanelController?.load(format: format, data: payload)
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    @objc private func handlePreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesController(
                config: appConfig ?? configService.loadConfig(),
                onSave: { [weak self] config in
                    self?.applyConfig(config)
                }
            )
        }
        preferencesController?.show()
    }

    private func showToast(message: String) {
        NotificationService.shared.send(message: message)
    }

    private func configureHotkey(using config: ConfigService.HotkeyConfig) {
        let parsed = HotkeyParser.parse(config.shortcut)
        hotkeyController?.unregister()
        hotkeyController = HotkeyController(
            modifiers: parsed.modifiers,
            keyCode: parsed.keyCode
        ) { [weak self] in
            self?.handleVisualizeClipboard()
        }
        hotkeyController?.register()
    }

    private func applyConfig(_ config: ConfigService.AppConfig) {
        appConfig = config
        Logger.enabled = config.debugLogging
        viewerPanelController?.applyUIConfig(config.ui)
        viewerPanelController?.applyPopoverConfig(config.popover)
        viewerPanelController?.applyScreenshotDirectory(config.screenshotDirectory)
        viewerPanelController?.applyScreenshotReveal(config.screenshotReveal)
        configureHotkey(using: config.hotkey)

        clipboardMonitor?.stop()
        clipboardMonitor = nil
        if config.clipboardMonitor.enabled {
            let monitor = ClipboardMonitor(pollIntervalMs: config.clipboardMonitor.pollIntervalMs) { [weak self] text in
                guard let self else { return }
                if text.utf8.count > 5_000_000 { return }
                guard let format = self.formatDetector.detectFormat(for: text) else { return }
                if config.clipboardMonitor.autoShow {
                    self.viewerPanelController?.show()
                    self.viewerPanelController?.load(format: format, data: text)
                }
            }
            clipboardMonitor = monitor
            monitor.start()
        }
    }

    private func normalizeXYZ(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { return text }
        let line1 = lines[1].trimmingCharacters(in: .whitespaces)
        if line1.isEmpty {
            return text
        }
        if !looksLikeAtomRecord(line1) {
            return text
        }
        var normalized = [String]()
        normalized.reserveCapacity(lines.count + 1)
        normalized.append(lines[0])
        normalized.append("")
        normalized.append(contentsOf: lines.dropFirst(1))
        return normalized.joined(separator: "\n")
    }

    private func looksLikeAtomRecord(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 4 else { return false }
        let numeric = tokens[1...3].allSatisfy { Double($0) != nil }
        return numeric
    }
}
