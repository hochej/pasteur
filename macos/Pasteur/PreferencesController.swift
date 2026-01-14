import AppKit

final class PreferencesController: NSObject {
    private let window: NSWindow
    private let hotkeyField = NSTextField()
    private let clipboardEnabledCheckbox = NSButton(checkboxWithTitle: "Monitor clipboard", target: nil, action: nil)
    private let autoShowCheckbox = NSButton(checkboxWithTitle: "Auto-show on match", target: nil, action: nil)
    private let pollIntervalField = NSTextField()
    private let screenshotRevealCheckbox = NSButton(checkboxWithTitle: "Reveal screenshots in Finder", target: nil, action: nil)
    private let debugLoggingCheckbox = NSButton(checkboxWithTitle: "Enable debug logging", target: nil, action: nil)
    private let opacitySlider = NSSlider()
    private let onSave: (ConfigService.AppConfig) -> Void
    private var baseConfig: ConfigService.AppConfig

    init(config: ConfigService.AppConfig, onSave: @escaping (ConfigService.AppConfig) -> Void) {
        self.baseConfig = config
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 290),
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
        let opacityRow = labeledSliderRow(title: "Panel opacity", slider: opacitySlider, minValue: 0.2, maxValue: 1.0)

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
        stack.addArrangedSubview(opacityRow)
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

    private func labeledSliderRow(title: String, slider: NSSlider, minValue: Double, maxValue: Double) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.numberOfTickMarks = 0
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.stringValue = String(format: "%.0f%%", slider.doubleValue * 100)

        slider.target = self
        slider.action = #selector(opacitySliderChanged(_:))

        let row = NSStackView(views: [label, slider, valueLabel])
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
        opacitySlider.doubleValue = config.ui.panelAlpha
        // Update the percentage label
        if let superview = opacitySlider.superview as? NSStackView,
           let valueLabel = superview.arrangedSubviews.last as? NSTextField {
            valueLabel.stringValue = String(format: "%.0f%%", config.ui.panelAlpha * 100)
        }
    }

    @objc private func handleCancel() {
        window.orderOut(nil)
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        // Update the percentage label
        if let superview = sender.superview as? NSStackView,
           let valueLabel = superview.arrangedSubviews.last as? NSTextField {
            valueLabel.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
        }
    }

    @objc private func handleSave() {
        let hotkey = hotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pollInterval = Int(pollIntervalField.stringValue) ?? baseConfig.clipboardMonitor.pollIntervalMs
        let clipboardEnabled = clipboardEnabledCheckbox.state == .on
        let autoShow = autoShowCheckbox.state == .on
        let screenshotReveal = screenshotRevealCheckbox.state == .on
        let debugLogging = debugLoggingCheckbox.state == .on
        let panelAlpha = opacitySlider.doubleValue

        let clipboardConfig = ConfigService.ClipboardMonitorConfig(
            enabled: clipboardEnabled,
            autoShow: autoShow,
            pollIntervalMs: max(100, pollInterval)
        )
        let hotkeyConfig = ConfigService.HotkeyConfig(
            shortcut: hotkey.isEmpty ? baseConfig.hotkey.shortcut : hotkey
        )

        let updatedUI = WebViewBridge.UIConfig(
            hud: baseConfig.ui.hud,
            overlayDelayMs: baseConfig.ui.overlayDelayMs,
            hideMolstarUi: baseConfig.ui.hideMolstarUi,
            panelAlpha: panelAlpha
        )

        let updated = ConfigService.AppConfig(
            ui: updatedUI,
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
