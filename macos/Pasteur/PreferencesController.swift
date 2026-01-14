import AppKit

final class PreferencesController: NSObject {
    private let window: NSWindow
    private let hotkeyField = NSTextField()
    private let clipboardEnabledCheckbox = NSButton(checkboxWithTitle: "Monitor clipboard", target: nil, action: nil)
    private let autoShowCheckbox = NSButton(checkboxWithTitle: "Auto-show on match", target: nil, action: nil)
    private let pollIntervalField = NSTextField()
    private let screenshotRevealCheckbox = NSButton(checkboxWithTitle: "Reveal screenshots in Finder", target: nil, action: nil)
    private let debugLoggingCheckbox = NSButton(checkboxWithTitle: "Enable debug logging", target: nil, action: nil)
    private let onSave: (ConfigService.AppConfig) -> Void
    private var baseConfig: ConfigService.AppConfig

    init(config: ConfigService.AppConfig, onSave: @escaping (ConfigService.AppConfig) -> Void) {
        self.baseConfig = config
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pasteur Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        super.init()

        setupView()
        applyConfig(config)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupView() {
        guard let contentView = window.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let hotkeyRow = labeledRow(title: "Hotkey", field: hotkeyField)
        let pollRow = labeledRow(title: "Poll interval (ms)", field: pollIntervalField)

        let buttonRow = NSStackView(views: [clipboardEnabledCheckbox, autoShowCheckbox])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 16
        buttonRow.alignment = .centerY

        let footerRow = NSStackView(views: [screenshotRevealCheckbox, debugLoggingCheckbox])
        footerRow.orientation = .horizontal
        footerRow.spacing = 16
        footerRow.alignment = .centerY

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 12
        actions.alignment = .centerY
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(handleCancel))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(handleSave))
        saveButton.keyEquivalent = "\r"
        actions.addArrangedSubview(cancelButton)
        actions.addArrangedSubview(saveButton)

        stack.addArrangedSubview(hotkeyRow)
        stack.addArrangedSubview(buttonRow)
        stack.addArrangedSubview(pollRow)
        stack.addArrangedSubview(footerRow)
        stack.addArrangedSubview(actions)

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])
    }

    private func labeledRow(title: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        field.placeholderString = title

        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func applyConfig(_ config: ConfigService.AppConfig) {
        hotkeyField.stringValue = config.hotkey.shortcut
        pollIntervalField.stringValue = String(config.clipboardMonitor.pollIntervalMs)
        clipboardEnabledCheckbox.state = config.clipboardMonitor.enabled ? .on : .off
        autoShowCheckbox.state = config.clipboardMonitor.autoShow ? .on : .off
        screenshotRevealCheckbox.state = config.screenshotReveal ? .on : .off
        debugLoggingCheckbox.state = config.debugLogging ? .on : .off
    }

    @objc private func handleCancel() {
        window.orderOut(nil)
    }

    @objc private func handleSave() {
        let hotkey = hotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pollInterval = Int(pollIntervalField.stringValue) ?? baseConfig.clipboardMonitor.pollIntervalMs
        let clipboardEnabled = clipboardEnabledCheckbox.state == .on
        let autoShow = autoShowCheckbox.state == .on
        let screenshotReveal = screenshotRevealCheckbox.state == .on
        let debugLogging = debugLoggingCheckbox.state == .on

        let clipboardConfig = ConfigService.ClipboardMonitorConfig(
            enabled: clipboardEnabled,
            autoShow: autoShow,
            pollIntervalMs: max(100, pollInterval)
        )
        let hotkeyConfig = ConfigService.HotkeyConfig(
            shortcut: hotkey.isEmpty ? baseConfig.hotkey.shortcut : hotkey
        )

        let updated = ConfigService.AppConfig(
            ui: baseConfig.ui,
            popover: baseConfig.popover,
            clipboardMonitor: clipboardConfig,
            screenshotDirectory: baseConfig.screenshotDirectory,
            screenshotReveal: screenshotReveal,
            hotkey: hotkeyConfig,
            debugLogging: debugLogging
        )

        baseConfig = updated
        onSave(updated)
        window.orderOut(nil)
    }
}
