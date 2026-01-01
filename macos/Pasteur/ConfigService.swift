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
                debugLogging: false
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
            return AppConfig(
                ui: ui,
                popover: popover,
                clipboardMonitor: clipboard,
                screenshotDirectory: screenshotDir,
                screenshotReveal: screenshotReveal,
                hotkey: hotkey,
                debugLogging: debugLogging
            )
        } catch {
            print("[Pasteur] Failed to parse config at \(url.path): \(error)")
            return AppConfig(
                ui: defaultUIConfig(),
                popover: defaultPopoverConfig(),
                clipboardMonitor: defaultClipboardConfig(),
                screenshotDirectory: defaultScreenshotDirectory(),
                screenshotReveal: false,
                hotkey: defaultHotkeyConfig(),
                debugLogging: false
            )
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
    }
}
