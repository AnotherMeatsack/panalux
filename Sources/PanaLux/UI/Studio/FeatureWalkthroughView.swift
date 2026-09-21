import SwiftUI
import WebKit

/// The real reference renderer, with guided highlights; exports open the full browser guide.
struct FeatureWalkthroughView: View {
    @ObservedObject var tour = FeatureWalkthroughController.shared
    var body: some View {
        if let index = tour.index {
            let step = tour.manifest.steps[index]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Discover PanaLux \(tour.manifest.version)").font(.headline)
                    Spacer()
                    Text("Step \(index + 1) of \(tour.manifest.steps.count)").font(.subheadline.monospacedDigit())
                }
                Text(step.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(step.body).font(.body).fixedSize(horizontal: false, vertical: true)
                FeatureReferenceWeb(step: step)
                    .frame(minHeight: 260)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                HStack {
                    Button("Later — keep unfinished") { tour.later() }
                    Button("Open full guide in browser") { ReferenceCard.open() }
                    if step.id == "contact" {
                        Button {
                            ContactWindowController.shared.show(kind: .question)
                        } label: {
                            Label("Open Contact", systemImage: "envelope")
                        }
                    }
                    if step.id == "soft-edge" || step.id == "intro-color" {
                        Button {
                            GuideController.shared.presentIntro()
                        } label: {
                            Label("Watch the Intro", systemImage: "play.rectangle")
                        }
                    }
                    if step.id == "lightshow" {
                        Button {
                            PanelLightShow.shared.start()
                        } label: {
                            Label("Play Light Show", systemImage: "sparkles")
                        }
                    }
                    Spacer()
                    if index > 0 { Button("Back") { tour.move(index - 1) } }
                    Button(index == tour.manifest.steps.count - 1 ? "Done" : "Next") {
                        if index == tour.manifest.steps.count - 1 { tour.done() }
                        else { tour.move(index + 1) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .background(.background)
        }
    }
}

struct FeatureReferenceWeb: NSViewRepresentable {
    let step: FeatureWalkthroughManifest.Step
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        context.coordinator.step = step
        var html = ReferenceCard.html(for: StudioEngine.shared)
        // The tutorial uses the actual controls and panel. Export targets remain visible,
        // but opening dialogs/downloads belongs to the full guide, not an embedded preview.
        html = html.replacingOccurrences(of: "</head>", with: """
        <style>.toolbar{position:relative}.inspector{position:relative;bottom:auto}.tour-focus{outline:4px solid #d46b0b!important;outline-offset:4px;background-color:#fff2d7!important;color:#18333e!important}.tour-focus rect{stroke:#d46b0b!important;stroke-width:3!important;fill:#fff2d7!important}.print-tools button{cursor:default} .hint{font-weight:600}</style></head>
        """)
        html = html.replacingOccurrences(of: "</body>", with: """
        <script>
        document.querySelectorAll('.print-tools button').forEach(b=>{b.removeAttribute('onclick');b.setAttribute('aria-disabled','true');});
        document.querySelector('.hint').textContent='Interactive practice: use Map, gestures and Zoom here. For printing or saving, choose Open full guide in browser below.';
        function tourStep(target,g,z){
          selectMap(document.getElementById("map").value);gesture(g);zoomPanel(z);
          document.querySelectorAll('.tour-focus').forEach(e=>e.classList.remove('tour-focus'));
          const selectors={launcher:'.toolbar strong',chord:'.state.selected .holds [data-ref="PREV_STILL"],.state.selected .holds [data-ref="NEXT_STILL"]',map:'#map',gestures:'#taps,#holds,#both,#atlas',zoom:'#zoom',print:'.print-tools button:not(#savepng)',png:'#savepng',replay:'.toolbar strong'};
          document.querySelectorAll(selectors[target]).forEach(e=>e.classList.add('tour-focus'));
          window.scrollTo(0,0);
        }
        </script></body>
        """)
        web.loadHTMLString(html, baseURL: nil)
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        guard context.coordinator.step?.id != step.id else { return }
        context.coordinator.step = step
        context.coordinator.apply(web)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var step: FeatureWalkthroughManifest.Step?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { apply(webView) }
        func apply(_ web: WKWebView) {
            guard let step, let data = try? JSONSerialization.data(withJSONObject: [step.target, step.gesture, step.zoom]),
                  let args = String(data: data, encoding: .utf8) else { return }
            web.evaluateJavaScript("tourStep(...\(args))", completionHandler: nil)
        }
    }
}
