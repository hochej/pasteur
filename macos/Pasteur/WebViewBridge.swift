import Foundation
import WebKit

protocol WebViewBridgeDelegate: AnyObject {
    func webViewBridgeDidBecomeReady(_ bridge: WebViewBridge)
    func webViewBridge(_ bridge: WebViewBridge, didLoad id: String)
    func webViewBridge(_ bridge: WebViewBridge, didError id: String?, message: String)
    func webViewBridge(_ bridge: WebViewBridge, didExport data: String, id: String)
    func webViewBridge(_ bridge: WebViewBridge, didRequestCopy text: String)
    func webViewBridgeDidRequestClose(_ bridge: WebViewBridge)
    func webViewBridge(_ bridge: WebViewBridge, didCaptureScreenshot data: String)
}

final class WebViewBridge: NSObject {
    static let channelName = "pasteur"

    struct LoadRequest: Codable {
        let id: String
        let format: String
        let data: String
        let options: [String: String]?
    }

    struct ExportRequest: Codable {
        let id: String
        let targetFormat: String
    }

    struct UIConfig: Codable {
        let hud: HUDConfig
        let overlayDelayMs: Int
        let hideMolstarUi: Bool
        let panelAlpha: Double

        struct HUDConfig: Codable {
            let visible: Bool
            let compact: Bool
            let showStatus: Bool
            let buttons: [String]
        }
    }

    weak var delegate: WebViewBridgeDelegate?

    private weak var webView: WKWebView?
    private var isReady = false
    private var pendingLoad: LoadRequest?
    private var pendingConfig: UIConfig?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    func sendLoad(_ request: LoadRequest) {
        guard isReady else {
            pendingLoad = request
            return
        }

        print("[Pasteur] Sending load id=\(request.id) format=\(request.format) bytes=\(request.data.utf8.count)")
        invoke(function: "loadFromNative", payload: request)
    }

    func sendConfig(_ config: UIConfig) {
        guard isReady else {
            pendingConfig = config
            return
        }
        invoke(function: "configureFromNative", payload: config)
    }

    func markReadyFromNative() {
        guard !isReady else { return }
        isReady = true
        if let pendingConfig {
            self.pendingConfig = nil
            sendConfig(pendingConfig)
        }
        if let pendingLoad {
            self.pendingLoad = nil
            sendLoad(pendingLoad)
        }
    }

    func sendClear() {
        evaluate(function: "clearFromNative")
    }

    func sendExport(_ request: ExportRequest) {
        invoke(function: "exportFromNative", payload: request)
    }

    private func invoke<T: Encodable>(function: String, payload: T) {
        guard let json = encodeJSON(payload) else { return }
        let js = "window.Pasteur?.\(function)(\(json));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func evaluate(function: String) {
        let js = "window.Pasteur?.\(function)();"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func encodeJSON<T: Encodable>(_ payload: T) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension WebViewBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.channelName else { return }
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            delegate?.webViewBridgeDidBecomeReady(self)
            if let pendingConfig {
                self.pendingConfig = nil
                sendConfig(pendingConfig)
            }
            if let pendingLoad {
                self.pendingLoad = nil
                sendLoad(pendingLoad)
            }
        case "loaded":
            let id = body["id"] as? String ?? ""
            delegate?.webViewBridge(self, didLoad: id)
        case "error":
            let id = body["id"] as? String
            let messageText = body["message"] as? String ?? "Unknown error"
            delegate?.webViewBridge(self, didError: id, message: messageText)
        case "exportResult":
            guard let id = body["id"] as? String,
                  let data = body["data"] as? String else { return }
            delegate?.webViewBridge(self, didExport: data, id: id)
        case "screenshotResult":
            guard let data = body["data"] as? String else { return }
            delegate?.webViewBridge(self, didCaptureScreenshot: data)
        case "log":
            let level = body["level"] as? String ?? "log"
            let messageText = body["message"] as? String ?? ""
            print("[Pasteur][JS][\(level)] \(messageText)")
        case "copyRequest":
            guard let text = body["data"] as? String else { return }
            delegate?.webViewBridge(self, didRequestCopy: text)
        case "closeRequest":
            delegate?.webViewBridgeDidRequestClose(self)
        default:
            break
        }
    }
}
