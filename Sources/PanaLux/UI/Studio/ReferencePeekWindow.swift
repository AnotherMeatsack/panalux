import AppKit
import WebKit
import Combine

/// A nonactivating panel: Lightroom keeps keyboard focus while the hardware chord is held.
final class ReferencePeekWindow: NSObject, WKNavigationDelegate {
    static let shared = ReferencePeekWindow()
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var observation: AnyCancellable?
    private var lastHTML = ""

    func setVisible(_ visible: Bool) {
        guard !AppRuntime.isRenderingStills else { return }
        guard visible else {
            panel?.orderOut(nil)
            observation = nil
            lastHTML = ""
            return
        }
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.appearance = NSAppearance(named: .aqua)
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            let web = WKWebView()
            web.navigationDelegate = self
            web.setValue(false, forKey: "drawsBackground")
            web.autoresizingMask = [.width, .height]
            let surface: NSView
            if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
               !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                let glass = NSGlassEffectView()
                glass.cornerRadius = 24
                glass.style = .regular
                glass.contentView = web
                surface = glass
            } else {
                let effect = NSVisualEffectView()
                effect.material = .hudWindow
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.wantsLayer = true
                effect.layer?.cornerRadius = 24
                effect.layer?.masksToBounds = true
                effect.addSubview(web)
                surface = effect
            }
            panel.contentView = surface
            web.frame = surface.bounds
            self.webView = web
            self.panel = panel
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let area = screen.visibleFrame.insetBy(dx: 24, dy: 24)
            let size = NSSize(width: min(1800, area.width), height: min(1250, area.height))
            panel?.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        }
        refresh()
        observation = StudioEngine.shared.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        panel?.orderFrontRegardless()
    }

    private func refresh() {
        let engine = StudioEngine.shared
        let fingerprint = engine.referenceContext + String(data: (try? JSONEncoder().encode(engine.currentHelpProfile())) ?? Data(), encoding: .utf8)!
        guard fingerprint != lastHTML else { return }
        let html = SVGPanelReference.document(states: SVGPanelReference.states(for: engine), peek: true)
        lastHTML = fingerprint
        webView?.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The real SVG adapts to the viewport; region zoom is available without activation.
        webView.evaluateJavaScript("fitReference()", completionHandler: nil)
    }
}
