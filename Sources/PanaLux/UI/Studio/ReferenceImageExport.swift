import AppKit
import UniformTypeIdentifiers
import WebKit

/// Render a self-contained reference card, without opening the panel or Lightroom.
@MainActor
final class ReferenceImageExport: NSObject, WKNavigationDelegate {
    private static var active: ReferenceImageExport?
    private var webView: WKWebView?
    private var destination: URL?
    private var timeout: DispatchWorkItem?
    private var completion: ((Error?) -> Void)?

    static func save(overview: Bool = false) {
        guard active == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PanaLux Current Panel.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        render(html: PanelReference.current(StudioEngine.shared).html, to: url) { error in
            if let error { NSAlert(error: error).runModal() }
            else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    static func render(html: String, to url: URL, completion: @escaping (Error?) -> Void) {
        guard active == nil else {
            completion(NSError(domain: "PanaLux", code: 3, userInfo: [NSLocalizedDescriptionKey: "A reference image is already being saved."]))
            return
        }
        let exporter = ReferenceImageExport()
        active = exporter
        exporter.destination = url
        exporter.completion = completion
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        exporter.webView = web
        web.navigationDelegate = exporter
        let html = html.replacingOccurrences(of: "</style>", with: ".noprint { display:none; }</style>")
        let timeout = DispatchWorkItem { [weak exporter] in
            exporter?.finish(NSError(domain: "PanaLux", code: 4, userInfo: [NSLocalizedDescriptionKey: "The reference image took too long to render. Try the printable reference instead."]))
        }
        exporter.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.scrollHeight") { [self] result, error in
            if let error { finish(error); return }
            guard let height = result as? Double, height > 0, height <= 12000 else {
                finish(NSError(domain: "PanaLux", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "This map is too tall for one image. Use Print Reference Card to save a multipage PDF."]))
                return
            }
            webView.setFrameSize(NSSize(width: 1400, height: height))
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: 1400, height: height)
            configuration.snapshotWidth = 1400
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { [self] image, error in
                if let error { finish(error); return }
                do {
                    guard let image, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]),
                          let destination else {
                        throw NSError(domain: "PanaLux", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render the reference image."])
                    }
                    try png.write(to: destination, options: .atomic)
                    finish(nil)
                } catch { finish(error) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(NSError(domain: "PanaLux", code: 5, userInfo: [NSLocalizedDescriptionKey: "The reference renderer stopped. Try saving again."]))
    }

    private func finish(_ error: Error?) {
        guard Self.active === self else { return }
        timeout?.cancel()
        timeout = nil
        webView?.navigationDelegate = nil
        webView = nil
        Self.active = nil
        completion?(error)
        completion = nil
    }
}
