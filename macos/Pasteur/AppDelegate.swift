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
        NSApp.setActivationPolicy(.accessory)

        let config = configService.loadConfig()
        appConfig = config
        Logger.enabled = config.debugLogging
        Logger.log("[Pasteur] Application did finish launching.")
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
                    let payload = format == "xyz" ? self.normalizeXYZ(text) : text
                    Logger.log("[Pasteur] Clipboard match format=\(format) bytes=\(text.utf8.count)")
                    DispatchQueue.main.async {
                        if clipboardConfig.autoShow {
                            self.viewerPanelController?.show()
                            self.viewerPanelController?.load(format: format, data: payload)
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
                let payload = format == "xyz" ? normalizeXYZ(text) : text
                DispatchQueue.main.async { [weak self] in
                    self?.viewerPanelController?.show()
                    self?.viewerPanelController?.load(format: format, data: payload)
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
        let config = appConfig ?? configService.loadConfig()
        preferencesController = PreferencesController(
            config: config,
            onSave: { [weak self] updated in
                self?.configService.saveConfig(updated)
                self?.applyConfig(updated)
            }
        )
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
                let payload = format == "xyz" ? self.normalizeXYZ(text) : text
                if config.clipboardMonitor.autoShow {
                    self.viewerPanelController?.show()
                    self.viewerPanelController?.load(format: format, data: payload)
                }
            }
            clipboardMonitor = monitor
            monitor.start()
        }
    }

    private func normalizeXYZ(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return text }

        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }

        if let countInfo = parseXYZCountLine(trimmed[0]) {
            var nextIndex = 1
            var commentLine = ""

            if let inlineComment = countInfo.comment, !inlineComment.isEmpty {
                commentLine = inlineComment
            } else if lines.count > 1 {
                let candidate = trimmed[1]
                if looksLikeAtomRecord(candidate) {
                    commentLine = ""
                } else {
                    commentLine = lines[1]
                    nextIndex = 2
                }
            }

            let atomLines = lines.dropFirst(nextIndex)
            guard let firstAtom = atomLines.first?.trimmingCharacters(in: .whitespaces),
                  looksLikeAtomRecord(firstAtom) else {
                return text
            }

            var normalized = [String]()
            normalized.reserveCapacity(atomLines.count + 2)
            normalized.append(String(countInfo.count))
            normalized.append(commentLine)
            normalized.append(contentsOf: atomLines)
            return normalized.joined(separator: "\n")
        }

        if looksLikeAtomRecord(trimmed[0]) {
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let atomRecordLines = nonEmptyLines.filter { looksLikeAtomRecord($0.trimmingCharacters(in: .whitespaces)) }
            guard atomRecordLines.count == nonEmptyLines.count else { return text }

            var normalized = [String]()
            normalized.reserveCapacity(atomRecordLines.count + 2)
            normalized.append(String(atomRecordLines.count))
            normalized.append("")
            normalized.append(contentsOf: nonEmptyLines)
            return normalized.joined(separator: "\n")
        }

        return text
    }

    private func parseXYZCountLine(_ line: String) -> (count: Int, comment: String?)? {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard let firstToken = tokens.first, let count = Int(firstToken), count > 0 else {
            return nil
        }
        let comment = tokens.dropFirst().joined(separator: " ")
        return (count, comment.isEmpty ? nil : comment)
    }

    private func looksLikeAtomRecord(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 4 else { return false }
        let numeric = tokens[1...3].allSatisfy { Double($0) != nil }
        return numeric
    }
}
