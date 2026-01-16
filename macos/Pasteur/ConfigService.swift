import Foundation

final class ConfigService {
    private let fileManager = FileManager.default

    struct PopoverConfig: Codable {
        let width: Double?
        let height: Double?
    }

    struct AppConfig {
        let ui: WebViewBridge.UIConfig
        let popover: PopoverConfig
        let clipboardMonitor: ClipboardMonitorConfig
        let screenshotDirectory: URL
        let screenshotReveal: Bool
        let hotkey: HotkeyConfig
        let debugLogging: Bool
        let openBabelPath: String
    }

    func loadConfig() -> AppConfig {
        let url = configURL()
        guard let data = try? Data(contentsOf: url) else {
            return AppConfig(
                ui: defaultUIConfig(),
                popover: defaultPopoverConfig(),
                clipboardMonitor: defaultClipboardConfig(),
                screenshotDirectory: defaultScreenshotDirectory(),
                screenshotReveal: false,
                hotkey: defaultHotkeyConfig(),
                debugLogging: false,
                openBabelPath: defaultOpenBabelPath()
            )
        }
        do {
            let fileConfig = try JSONDecoder().decode(FileConfig.self, from: data)
            let ui = mergeUIConfig(fileConfig)
            let popover = fileConfig.popover ?? defaultPopoverConfig()
            let clipboard = fileConfig.clipboardMonitor ?? defaultClipboardConfig()
            let screenshotDir = resolveScreenshotDirectory(fileConfig.screenshotDirectory)
            let screenshotReveal = fileConfig.screenshotReveal ?? false
            let hotkey = fileConfig.hotkey ?? defaultHotkeyConfig()
            let debugLogging = fileConfig.debugLogging ?? false
            let openBabelPath = fileConfig.openBabelPath ?? defaultOpenBabelPath()
            return AppConfig(
                ui: ui,
                popover: popover,
                clipboardMonitor: clipboard,
                screenshotDirectory: screenshotDir,
                screenshotReveal: screenshotReveal,
                hotkey: hotkey,
                debugLogging: debugLogging,
                openBabelPath: openBabelPath
            )
        } catch {
            Logger.log("[Pasteur] Failed to parse config at \(url.path): \(error)")
            return AppConfig(
                ui: defaultUIConfig(),
                popover: defaultPopoverConfig(),
                clipboardMonitor: defaultClipboardConfig(),
                screenshotDirectory: defaultScreenshotDirectory(),
                screenshotReveal: false,
                hotkey: defaultHotkeyConfig(),
                debugLogging: false,
                openBabelPath: defaultOpenBabelPath()
            )
        }
    }

    func saveConfig(_ config: AppConfig) {
        let url = configURL()
        let fileConfig = FileConfig(
            hud: config.ui.hud,
            overlayDelayMs: config.ui.overlayDelayMs,
            hideMolstarUi: config.ui.hideMolstarUi,
            panelAlpha: config.ui.panelAlpha,
            popover: config.popover,
            clipboardMonitor: config.clipboardMonitor,
            screenshotDirectory: pathForConfig(config.screenshotDirectory),
            screenshotReveal: config.screenshotReveal,
            hotkey: config.hotkey,
            debugLogging: config.debugLogging,
            openBabelPath: config.openBabelPath
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(fileConfig)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.log("[Pasteur] Failed to save config: \(error)")
        }
    }

    private func configURL() -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".pasteur/config.json")
    }

    private func defaultUIConfig() -> WebViewBridge.UIConfig {
        WebViewBridge.UIConfig(
            hud: .init(
                visible: false,
                compact: true,
                showStatus: false,
                buttons: []
            ),
            overlayDelayMs: 200,
            hideMolstarUi: true,
            panelAlpha: 0.7
        )
    }

    private func defaultPopoverConfig() -> PopoverConfig {
        PopoverConfig(width: 720, height: 520)
    }

    struct ClipboardMonitorConfig: Codable {
        let enabled: Bool
        let autoShow: Bool
        let pollIntervalMs: Int
    }

    private func defaultClipboardConfig() -> ClipboardMonitorConfig {
        ClipboardMonitorConfig(enabled: false, autoShow: false, pollIntervalMs: 500)
    }

    struct HotkeyConfig: Codable {
        let shortcut: String
    }

    private func defaultHotkeyConfig() -> HotkeyConfig {
        HotkeyConfig(shortcut: "ctrl+opt+cmd+m")
    }

    private func defaultOpenBabelPath() -> String {
        "/opt/homebrew/bin/obabel"
    }

    private func defaultScreenshotDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
    }

    private func resolveScreenshotDirectory(_ path: String?) -> URL {
        guard let path, !path.isEmpty else {
            return defaultScreenshotDirectory()
        }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func pathForConfig(_ url: URL) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(home) {
            let suffix = path.dropFirst(home.count)
            return "~" + suffix
        }
        return path
    }

    private func mergeUIConfig(_ fileConfig: FileConfig) -> WebViewBridge.UIConfig {
        let defaults = defaultUIConfig()
        return WebViewBridge.UIConfig(
            hud: fileConfig.hud ?? defaults.hud,
            overlayDelayMs: fileConfig.overlayDelayMs ?? defaults.overlayDelayMs,
            hideMolstarUi: fileConfig.hideMolstarUi ?? defaults.hideMolstarUi,
            panelAlpha: fileConfig.panelAlpha ?? defaults.panelAlpha
        )
    }

    private struct FileConfig: Codable {
        let hud: WebViewBridge.UIConfig.HUDConfig?
        let overlayDelayMs: Int?
        let hideMolstarUi: Bool?
        let panelAlpha: Double?
        let popover: PopoverConfig?
        let clipboardMonitor: ClipboardMonitorConfig?
        let screenshotDirectory: String?
        let screenshotReveal: Bool?
        let hotkey: HotkeyConfig?
        let debugLogging: Bool?
        let openBabelPath: String?
    }
}
