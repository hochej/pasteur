import AppKit
import WebKit

final class ViewerPanelController: NSObject {
    private let popover: NSPopover
    private let contentController: NSViewController
    private let webView: WKWebView
    private let bridge: WebViewBridge
    private let clipboardService = ClipboardService()
    private let schemeHandler = WebAssetSchemeHandler()
    private weak var anchorButton: NSStatusBarButton?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var panelAlpha: CGFloat = 0.7
    private var screenshotDirectory: URL?

    override init() {
        print("[Pasteur] ViewerPanelController init start.")
        let webContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = webContentController
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebAssetSchemeHandler.scheme)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        contentController = NSViewController()
        contentController.view = webView

        popover = NSPopover()
        popover.contentViewController = contentController
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 720, height: 520)

        bridge = WebViewBridge(webView: webView)

        super.init()

        bridge.delegate = self
        webView.navigationDelegate = self
        webContentController.add(bridge, name: WebViewBridge.channelName)
        loadWebViewer()
        print("[Pasteur] ViewerPanelController init complete.")
    }

    func setAnchorButton(_ button: NSStatusBarButton?) {
        anchorButton = button
    }

    func applyPopoverConfig(_ config: ConfigService.PopoverConfig) {
        let width = max(360, config.width ?? popover.contentSize.width)
        let height = max(240, config.height ?? popover.contentSize.height)
        popover.contentSize = NSSize(width: width, height: height)
    }

    func applyScreenshotDirectory(_ url: URL) {
        screenshotDirectory = url
    }

    func show() {
        guard let button = anchorButton else { return }
        if popover.isShown {
            popover.performClose(nil)
            removeKeyMonitors()
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        applyPopoverAlphaIfNeeded()
        installKeyMonitors()
    }

    func hide() {
        popover.performClose(nil)
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
        contentController.view.wantsLayer = true
        contentController.view.layer?.backgroundColor = NSColor.clear.cgColor
        applyPopoverAlphaIfNeeded()
        print("[Pasteur] Applied panel alpha=\(clamped)")
    }

    private func loadWebViewer() {
        let resourceURL = Bundle.module.resourceURL ?? Bundle.main.resourceURL
        guard let rootURL = resourceURL else {
            print("[Pasteur] Missing resource URL for web assets.")
            return
        }
        let webRoot = rootURL.appendingPathComponent("web-dist", isDirectory: true)
        schemeHandler.assetRoot = webRoot
        let indexURL = URL(string: "\(WebAssetSchemeHandler.scheme)://index.html")
        let exists = FileManager.default.fileExists(atPath: webRoot.appendingPathComponent("index.html").path)
        print("[Pasteur] Loading web viewer from scheme=\(WebAssetSchemeHandler.scheme) exists=\(exists)")
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

    private func applyPopoverAlphaIfNeeded() {
        guard let window = contentController.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(panelAlpha)
    }

    deinit {
        removeKeyMonitors()
    }
}

extension ViewerPanelController: WebViewBridgeDelegate {
    func webViewBridgeDidBecomeReady(_ bridge: WebViewBridge) {
        print("[Pasteur] WebView bridge ready.")
    }

    func webViewBridge(_ bridge: WebViewBridge, didLoad id: String) {
        print("[Pasteur] Loaded structure id=\(id).")
    }

    func webViewBridge(_ bridge: WebViewBridge, didError id: String?, message: String) {
        let idText = id ?? "unknown"
        print("[Pasteur] Load error id=\(idText) message=\(message)")
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
            print("[Pasteur] Screenshot saved to \(url.path)")
        } catch {
            print("[Pasteur] Screenshot save failed: \(error)")
        }
    }
}

extension ViewerPanelController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[Pasteur] WebView finished loading.")
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
                print("[Pasteur] WebView probe failed: \(error)")
                return
            }
            guard let info = result as? [String: Any] else {
                print("[Pasteur] WebView probe returned unexpected result.")
                return
            }
            let hasPasteur = (info["hasPasteur"] as? Bool) ?? false
            let hasBridge = (info["hasBridge"] as? Bool) ?? false
            print("[Pasteur] WebView probe hasPasteur=\(hasPasteur) hasBridge=\(hasBridge)")
            if hasPasteur {
                self?.bridge.markReadyFromNative()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Pasteur] WebView failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[Pasteur] WebView provisional load failed: \(error)")
    }
}
