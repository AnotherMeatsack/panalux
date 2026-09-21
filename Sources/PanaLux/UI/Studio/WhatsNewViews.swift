import SwiftUI
import AppKit

/// Where each toolbar control sits in the window, so the spotlight can land on the real button.
final class ToolbarFrames: ObservableObject {
    static let shared = ToolbarFrames()
    /// Window coordinates, origin bottom-left.
    @Published var frames: [String: CGRect] = [:]
}

/// Reports its host view's frame in window coordinates. Toolbar items live outside the
/// content view, so a SwiftUI anchor cannot see them.
struct FrameReporter: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            let frame = view.convert(view.bounds, to: nil)
            if ToolbarFrames.shared.frames[id] != frame { ToolbarFrames.shared.frames[id] = frame }
        }
    }
}

extension View {
    func reportsFrame(_ id: String) -> some View { background(FrameReporter(id: id)) }
}

/// The list of changes since the version this person last used.
struct WhatsNewSheet: View {
    @ObservedObject var whatsNew = WhatsNewController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What’s new in PanaLux \(whatsNew.manifest.version)").font(.title2.bold())
                if let since = whatsNew.since {
                    Text("Changes since \(since.description)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(whatsNew.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.kind == "new" ? "NEW" : "UPDATED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(item.kind == "new" ? Color.accentColor : Color.orange))
                                .foregroundStyle(.white)
                                .frame(width: 72, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.headline)
                                Text(item.body).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            HStack {
                Text("Close this and PanaLux will point to each one.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { whatsNew.closeChangelog(showMeWhere: false) }
                Button("Show Me Where") { whatsNew.closeChangelog() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

/// Dims the window around the real control for each change, one at a time.
struct WhatsNewSpotlight: View {
    @ObservedObject var whatsNew = WhatsNewController.shared
    @ObservedObject var toolbar = ToolbarFrames.shared
    let anchors: [SpotlightAnchor: Anchor<CGRect>]
    @State private var origin: CGRect = .zero

    var body: some View {
        if let index = whatsNew.spotlightIndex, whatsNew.items.indices.contains(index) {
            let item = whatsNew.items[index]
            GeometryReader { geo in
                let hole = holeRect(item.target, in: geo)
                ZStack(alignment: .topLeading) {
                    SpotlightMask(hole: hole)
                        .animation(.smooth(duration: 0.35), value: hole)
                    card(item, index: index)
                        .frame(width: 380)
                        .position(cardPosition(hole: hole, in: geo.size))
                        .animation(.smooth(duration: 0.35), value: index)
                }
                .background(OriginProbe(origin: $origin))
            }
        }
    }

    private func toolbarKey(_ target: String) -> String? {
        ["guide": "guide", "help": "help", "settings": "settings"][target]
    }

    private func holeRect(_ target: String, in geo: GeometryProxy) -> CGRect {
        if target == "map", let a = anchors[.map] { return geo[a].insetBy(dx: -4, dy: -4) }
        if target == "inspector", let a = anchors[.inspector] { return geo[a].insetBy(dx: -4, dy: -4) }
        if let key = toolbarKey(target), let w = toolbar.frames[key], origin != .zero {
            // Window coordinates run bottom-up; this view's own frame is the reference.
            let x = w.minX - origin.minX
            let y = origin.maxY - w.maxY
            return CGRect(x: x, y: y, width: w.width, height: w.height).insetBy(dx: -8, dy: -6)
        }
        return CGRect(x: 0, y: -40, width: geo.size.width, height: 44)
    }

    private func cardPosition(hole: CGRect, in size: CGSize) -> CGPoint {
        let half: CGFloat = 200
        // Under a toolbar button, or over the lower part of the window for large areas.
        if hole.minY < 60 && hole.height < 80 {
            return CGPoint(x: min(max(hole.midX, half + 16), size.width - half - 16), y: hole.maxY + 130)
        }
        return CGPoint(x: size.width - half - 16, y: size.height - 150)
    }

    private func card(_ item: FeatureWalkthroughManifest.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) of \(whatsNew.items.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.title).font(.title3.weight(.semibold))
            Text(item.body).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let label = actionLabel(item.action) {
                Button(label) { perform(item.action) }
            }
            HStack {
                Button("End") { whatsNew.finish() }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                Spacer()
                if index > 0 { Button("Back") { whatsNew.move(-1) } }
                Button(index == whatsNew.items.count - 1 ? "Done" : "Next") { whatsNew.move(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .modifier(CalloutBackground())
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private func actionLabel(_ action: String?) -> String? {
        switch action {
        case "contact": return "Open Contact"
        case "intro": return "Watch the Intro"
        case "lightshow": return "Play Light Show"
        case "guide": return "Open the Panel Guide"
        default: return nil
        }
    }

    private func perform(_ action: String?) {
        switch action {
        case "contact": ContactWindowController.shared.show(kind: .question)
        case "intro": whatsNew.finish(); GuideController.shared.presentIntro()
        case "lightshow": PanelLightShow.shared.start()
        case "guide": ReferenceCard.open()
        default: break
        }
    }
}

/// Measures this view's frame in window coordinates.
private struct OriginProbe: NSViewRepresentable {
    @Binding var origin: CGRect
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            let frame = view.convert(view.bounds, to: nil)
            if origin != frame { origin = frame }
        }
    }
}
