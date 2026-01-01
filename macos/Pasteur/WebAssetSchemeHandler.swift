import Foundation
import WebKit

final class WebAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "pasteur"

    var assetRoot: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let assetRoot else {
            urlSchemeTask.didFailWithError(NSError(domain: "Pasteur", code: 1))
            return
        }

        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "Pasteur", code: 2))
            return
        }

        let host = url.host ?? ""
        let pathComponents = url.path.split(separator: "/").map(String.init)
        var components: [String] = []
        if !host.isEmpty {
            components.append(host)
        }
        components.append(contentsOf: pathComponents)
        var relativePath = components.joined(separator: "/")
        if relativePath.isEmpty {
            relativePath = "index.html"
        }

        let standardizedRoot = assetRoot.standardizedFileURL
        let candidateURL = assetRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard candidateURL.pathComponents.starts(with: standardizedRoot.pathComponents) else {
            print("[Pasteur] Scheme blocked traversal \(url.absoluteString)")
            urlSchemeTask.didFailWithError(NSError(domain: "Pasteur", code: 4))
            return
        }
        let fileURL = candidateURL
        print("[Pasteur] Scheme request \(url.absoluteString) -> \(fileURL.path)")

        guard let data = try? Data(contentsOf: fileURL) else {
            print("[Pasteur] Scheme failed to read \(fileURL.path)")
            urlSchemeTask.didFailWithError(NSError(domain: "Pasteur", code: 3))
            return
        }

        let mimeType = mimeTypeForPath(fileURL.path)
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op.
    }

    private func mimeTypeForPath(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".html") { return "text/html" }
        if lower.hasSuffix(".js") { return "application/javascript" }
        if lower.hasSuffix(".css") { return "text/css" }
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".svg") { return "image/svg+xml" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        if lower.hasSuffix(".woff") { return "font/woff" }
        if lower.hasSuffix(".woff2") { return "font/woff2" }
        if lower.hasSuffix(".ttf") { return "font/ttf" }
        if lower.hasSuffix(".wasm") { return "application/wasm" }
        return "application/octet-stream"
    }
}
