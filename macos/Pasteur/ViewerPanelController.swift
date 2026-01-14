import AppKit
import WebKit

final class ViewerPanelController: NSObject {
    private let panel: NSPanel
    private let webView: WKWebView
    private let bridge: WebViewBridge
    private let clipboardService = ClipboardService()
    private let schemeHandler = WebAssetSchemeHandler()
    private weak var anchorButton: NSStatusBarButton?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var panelAlpha: CGFloat = 0.7
    private var screenshotDirectory: URL?
    private var screenshotReveal = false
    private var didPrewarm = false
    private var popoverConfig = ConfigService.PopoverConfig(width: 720, height: 520)

    override init() {
        Logger.log("[Pasteur] ViewerPanelController init start.")
        let webContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = webContentController
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebAssetSchemeHandler.scheme)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = webView
        webView.frame = panel.contentView?.bounds ?? .zero
        webView.autoresizingMask = [.width, .height]
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true

        bridge = WebViewBridge(webView: webView)

        super.init()

        bridge.delegate = self
        webView.navigationDelegate = self
        webContentController.add(bridge, name: WebViewBridge.channelName)
        loadWebViewer()
        Logger.log("[Pasteur] ViewerPanelController init complete.")
    }

    func setAnchorButton(_ button: NSStatusBarButton?) {
        anchorButton = button
    }

    func applyPopoverConfig(_ config: ConfigService.PopoverConfig) {
        popoverConfig = config
        applyPanelSizing(using: popoverConfig, screen: anchorButton?.window?.screen)
    }

    func applyScreenshotDirectory(_ url: URL) {
        screenshotDirectory = url
    }

    func applyScreenshotReveal(_ reveal: Bool) {
        screenshotReveal = reveal
    }

    func show() {
        guard let button = anchorButton else { return }
        if panel.isVisible {
            hide()
            return
        }
        let screen = button.window?.screen
        applyPanelSizing(using: popoverConfig, screen: screen)
        positionPanel(near: button, screen: screen)
        applyPanelAlphaIfNeeded()
        panel.orderFrontRegardless()
        installKeyMonitors()
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitors()
    }

    func load(format: String, data: String) {
        let request = WebViewBridge.LoadRequest(
            id: UUID().uuidString,
            format: format,
            data: data,
            options: nil
        )
        bridge.sendLoad(request)
    }

    func applyUIConfig(_ config: WebViewBridge.UIConfig) {
        bridge.sendConfig(config)
        let clamped = max(0.2, min(1.0, CGFloat(config.panelAlpha)))
        panelAlpha = clamped
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        applyPanelAlphaIfNeeded()
        Logger.log("[Pasteur] Applied panel alpha=\(clamped)")
    }

    private func loadWebViewer() {
        let resourceURL = Bundle.module.resourceURL ?? Bundle.main.resourceURL
        guard let rootURL = resourceURL else {
            Logger.log("[Pasteur] Missing resource URL for web assets.")
            return
        }
        let webRoot = rootURL.appendingPathComponent("web-dist", isDirectory: true)
        schemeHandler.assetRoot = webRoot
        let indexURL = URL(string: "\(WebAssetSchemeHandler.scheme)://index.html")
        let exists = FileManager.default.fileExists(atPath: webRoot.appendingPathComponent("index.html").path)
        Logger.log("[Pasteur] Loading web viewer from scheme=\(WebAssetSchemeHandler.scheme) exists=\(exists)")
        if let indexURL {
            webView.load(URLRequest(url: indexURL))
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.shouldClose(for: event) {
                self.hide()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.shouldClose(for: event) {
                self.hide()
            }
        }
    }

    private func removeKeyMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }

    private func shouldClose(for event: NSEvent) -> Bool {
        event.keyCode == 49 || event.keyCode == 53
    }

    private func applyPanelAlphaIfNeeded() {
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.alphaValue = panelAlpha
    }

    private func applyPanelSizing(using config: ConfigService.PopoverConfig, screen: NSScreen?) {
        let currentSize = panel.contentRect(forFrameRect: panel.frame).size
        let rawWidth = config.width ?? currentSize.width
        let rawHeight = config.height ?? currentSize.height
        let minWidth: CGFloat = 360
        let minHeight: CGFloat = 240
        var width = max(minWidth, rawWidth)
        var height = max(minHeight, rawHeight)

        if let screen {
            let frame = screen.visibleFrame
            width = min(width, max(minWidth, frame.width - 40))
            height = min(height, max(minHeight, frame.height - 80))
        }

        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func positionPanel(near button: NSStatusBarButton, screen: NSScreen?) {
        guard let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.contentRect(forFrameRect: panel.frame).size
        let visibleFrame = (screen ?? window.screen)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var originX = buttonFrame.midX - panelSize.width / 2
        var originY = buttonFrame.minY - panelSize.height - 8

        if originX < visibleFrame.minX { originX = visibleFrame.minX + 20 }
        if originY < visibleFrame.minY { originY = visibleFrame.minY + 20 }
        if originX + panelSize.width > visibleFrame.maxX {
            originX = visibleFrame.maxX - panelSize.width - 20
        }
        if originY + panelSize.height > visibleFrame.maxY {
            originY = visibleFrame.maxY - panelSize.height - 20
        }

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    deinit {
        removeKeyMonitors()
    }
}

extension ViewerPanelController: WebViewBridgeDelegate {
    func webViewBridgeDidBecomeReady(_ bridge: WebViewBridge) {
        Logger.log("[Pasteur] WebView bridge ready.")
        if !didPrewarm, !bridge.hasPendingLoad {
            didPrewarm = true
            bridge.sendPrewarm()
        }
    }

    func webViewBridge(_ bridge: WebViewBridge, didLoad id: String) {
        Logger.log("[Pasteur] Loaded structure id=\(id).")
    }

    func webViewBridge(_ bridge: WebViewBridge, didError id: String?, message: String) {
        let idText = id ?? "unknown"
        Logger.log("[Pasteur] Load error id=\(idText) message=\(message)")
    }

    func webViewBridge(_ bridge: WebViewBridge, didRequestCopy text: String) {
        clipboardService.writeString(text)
    }

    func webViewBridgeDidRequestClose(_ bridge: WebViewBridge) {
        hide()
    }

    func webViewBridge(_ bridge: WebViewBridge, didExport data: String, id: String) {
        guard let decoded = Data(base64Encoded: data) else { return }

        let panel = NSSavePanel()
        panel.allowedFileTypes = ["molx"]
        panel.nameFieldStringValue = "Pasteur-Session.molx"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try decoded.write(to: url)
            } catch {
                // Non-fatal: ignore save errors for now.
            }
        }
    }

    func webViewBridge(_ bridge: WebViewBridge, didCaptureScreenshot data: String) {
        guard let decoded = Data(base64Encoded: data) else { return }
        let targetDir = screenshotDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let dir = targetDir else { return }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "\(formatter.string(from: Date())).png"
            let url = dir.appendingPathComponent(name)
            try decoded.write(to: url)
            Logger.log("[Pasteur] Screenshot saved to \(url.path)")
            if screenshotReveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            Logger.log("[Pasteur] Screenshot save failed: \(error)")
        }
    }
}

extension ViewerPanelController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.log("[Pasteur] WebView finished loading.")
        let probeScript = """
        (function() {
            return {
                hasPasteur: !!window.Pasteur,
                hasBridge: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pasteur)
            };
        })();
        """
        webView.evaluateJavaScript(probeScript) { [weak self] result, error in
            if let error {
                Logger.log("[Pasteur] WebView probe failed: \(error)")
                return
            }
            guard let info = result as? [String: Any] else {
                Logger.log("[Pasteur] WebView probe returned unexpected result.")
                return
            }
            let hasPasteur = (info["hasPasteur"] as? Bool) ?? false
            let hasBridge = (info["hasBridge"] as? Bool) ?? false
            Logger.log("[Pasteur] WebView probe hasPasteur=\(hasPasteur) hasBridge=\(hasBridge)")
            if hasPasteur {
                self?.bridge.markReadyFromNative()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.log("[Pasteur] WebView failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.log("[Pasteur] WebView provisional load failed: \(error)")
    }
}
