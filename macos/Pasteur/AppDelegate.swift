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
            controller.applyOpenBabelPath(config.openBabelPath)
            controller.setAnchorButton(self?.statusItemController?.button)
            Logger.log("[Pasteur] Viewer panel ready.")

            if config.clipboardMonitor.enabled {
                Logger.log("[Pasteur] Clipboard monitor enabled poll=\(config.clipboardMonitor.pollIntervalMs)ms autoShow=\(config.clipboardMonitor.autoShow)")
                self?.applyClipboardMonitor(config: config)
            }
        }

        if config.clipboardMonitor.enabled, config.clipboardMonitor.autoShow, let text = clipboardService.readString() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for file path
            if isFilePath(trimmed), let fileContents = readFile(atPath: trimmed) {
                if let format = formatDetector.detectFormat(for: fileContents) {
                    DispatchQueue.main.async { [weak self] in
                        self?.visualizeContent(fileContents, format: format)
                    }
                } else if let salvagedXYZ = salvageXYZPayload(from: fileContents) {
                    DispatchQueue.main.async { [weak self] in
                        self?.visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
                    }
                }
            } else if let format = formatDetector.detectFormat(for: trimmed) {
                DispatchQueue.main.async { [weak self] in
                    self?.visualizeContent(trimmed, format: format, rawText: text)
                }
            } else if let salvagedXYZ = salvageXYZPayload(from: text) {
                DispatchQueue.main.async { [weak self] in
                    self?.visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
                }
            }
        }

        configureHotkey(using: config.hotkey)
    }

    @objc private func handleVisualizeClipboard() {
        // Check if panel is already visible - if so, just toggle it off
        if viewerPanelController?.isVisible == true {
            viewerPanelController?.hide()
            return
        }

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

        // Check if it's a file path
        if isFilePath(trimmed) {
            if let fileContents = readFile(atPath: trimmed) {
                if let format = formatDetector.detectFormat(for: fileContents) {
                    visualizeContent(fileContents, format: format)
                    return
                }
                if let salvagedXYZ = salvageXYZPayload(from: fileContents) {
                    visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
                    return
                }
                showToast(message: "File doesn't contain a supported molecule format.")
            } else {
                showToast(message: "Could not read file.")
            }
            return
        }

        // Existing clipboard content handling
        if let format = formatDetector.detectFormat(for: trimmed) {
            visualizeContent(trimmed, format: format, rawText: rawText)
            return
        }

        // Salvage: allow accidental extra lines above/below XYZ blocks (e.g. shell prompts).
        if let salvagedXYZ = salvageXYZPayload(from: rawText) {
            visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
            return
        }

        showToast(message: "Clipboard doesn't look like a supported molecule format.")
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private func isFilePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file://")
    }

    private func readFile(atPath path: String) -> String? {
        var filePath = path

        if filePath.hasPrefix("file://") {
            filePath = String(filePath.dropFirst(7))
        }

        if filePath.hasPrefix("~") {
            filePath = (filePath as NSString).expandingTildeInPath
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            Logger.log("[Pasteur] File not found: \(filePath)")
            return nil
        }

        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            Logger.log("[Pasteur] Loaded file: \(filePath) (\(contents.count) chars)")
            return contents
        } catch {
            Logger.log("[Pasteur] Error reading file: \(error)")
            return nil
        }
    }

    private func visualizeContent(_ content: String, format: String, rawText: String? = nil) {
        viewerPanelController?.show()

        if format == "smiles" {
            viewerPanelController?.loadSMILES(content.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }

        if format == "xyz" {
            let base = rawText ?? content
            let salvaged = salvageXYZPayload(from: base) ?? base
            let payload = normalizeXYZ(salvaged)
            viewerPanelController?.load(format: format, data: payload)
            return
        }

        viewerPanelController?.load(format: format, data: content)
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
        viewerPanelController?.applyOpenBabelPath(config.openBabelPath)
        configureHotkey(using: config.hotkey)

        applyClipboardMonitor(config: config)
    }

    private func applyClipboardMonitor(config: ConfigService.AppConfig) {
        clipboardMonitor?.stop()
        clipboardMonitor = nil
        guard config.clipboardMonitor.enabled else { return }

        let monitor = ClipboardMonitor(pollIntervalMs: config.clipboardMonitor.pollIntervalMs) { [weak self] text in
            guard let self, config.clipboardMonitor.autoShow else { return }
            if text.utf8.count > 5_000_000 { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for file path first
            if self.isFilePath(trimmed), let fileContents = self.readFile(atPath: trimmed) {
                if let format = self.formatDetector.detectFormat(for: fileContents) {
                    self.visualizeContent(fileContents, format: format)
                } else if let salvagedXYZ = self.salvageXYZPayload(from: fileContents) {
                    self.visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
                }
                return
            }

            // Existing content handling
            if let format = self.formatDetector.detectFormat(for: trimmed) {
                self.visualizeContent(trimmed, format: format, rawText: text)
            } else if let salvagedXYZ = self.salvageXYZPayload(from: text) {
                self.visualizeContent(salvagedXYZ, format: "xyz", rawText: salvagedXYZ)
            }
        }
        clipboardMonitor = monitor
        monitor.start()
    }

    /// Attempts to recover valid XYZ content from a messy clipboard selection.
    ///
    /// Common failure mode: the user accidentally copies a shell prompt line or other
    /// noise above/below an XYZ block. Molstar's XYZ parser is fairly strict, so we
    /// try to extract the first complete XYZ frame (and any subsequent complete frames)
    /// and drop surrounding garbage.
    ///
    /// This is intentionally conservative: we only "salvage" when we can prove an XYZ
    /// frame exists (atom count line + N atom records).
    private func salvageXYZPayload(from text: String) -> String? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }

        func trimmedLine(_ index: Int) -> String {
            lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func parseFrame(startIndex i: Int) -> (range: Range<Int>, nextIndex: Int)? {
            let header = trimmedLine(i)
            guard let countInfo = parseXYZCountLine(header) else { return nil }
            let atomCount = countInfo.count
            guard atomCount > 0 else { return nil }

            let firstAfterHeader = i + 1
            guard firstAfterHeader < lines.count else { return nil }

            let atomStart: Int
            if looksLikeAtomRecord(trimmedLine(firstAfterHeader)) {
                // Non-standard XYZ (missing comment line): count is followed directly by atom records.
                atomStart = firstAfterHeader
            } else {
                // Standard XYZ: count + comment + atoms.
                atomStart = i + 2
            }

            let atomEndExclusive = atomStart + atomCount
            guard atomEndExclusive <= lines.count else { return nil }

            for j in atomStart..<atomEndExclusive {
                if !looksLikeAtomRecord(trimmedLine(j)) {
                    return nil
                }
            }

            return (i..<atomEndExclusive, atomEndExclusive)
        }

        // 1) Try to find a proper XYZ frame (count line + atoms) anywhere in the text.
        var firstFrameStart: Int?
        for i in 0..<lines.count {
            if parseFrame(startIndex: i) != nil {
                firstFrameStart = i
                break
            }
        }

        if let start = firstFrameStart {
            var extracted: [String] = []
            extracted.reserveCapacity(lines.count)

            var index = start
            while index < lines.count {
                // Allow blank separators between frames.
                while index < lines.count, trimmedLine(index).isEmpty {
                    index += 1
                }
                guard index < lines.count else { break }

                guard let frame = parseFrame(startIndex: index) else { break }
                extracted.append(contentsOf: lines[frame.range])
                index = frame.nextIndex
            }

            // Drop trailing empty lines we might have pulled in.
            while let last = extracted.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extracted.removeLast()
            }

            let result = extracted.joined(separator: "\n")
            return result.isEmpty ? nil : result
        }

        // 2) Fallback: headerless XYZ somewhere in the text (consecutive atom records).
        // This is useful when the user only copies coordinates.
        var i = 0
        while i < lines.count {
            if looksLikeAtomRecord(trimmedLine(i)) {
                var j = i
                while j < lines.count, looksLikeAtomRecord(trimmedLine(j)) {
                    j += 1
                }
                let count = j - i
                if count >= 3 {
                    var result: [String] = []
                    result.reserveCapacity(count + 2)
                    result.append(String(count))
                    result.append("")
                    result.append(contentsOf: lines[i..<j])
                    return result.joined(separator: "\n")
                }
                i = j
            } else {
                i += 1
            }
        }

        return nil
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
