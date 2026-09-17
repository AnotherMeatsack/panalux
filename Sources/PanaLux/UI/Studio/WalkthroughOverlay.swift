import SwiftUI

/// Dims the window around one area and explains it. Hardware steps advance on their own.
public struct WalkthroughOverlay: View {
    @ObservedObject var guide = GuideController.shared
    @ObservedObject var engine = StudioEngine.shared
    let anchors: [SpotlightAnchor: Anchor<CGRect>]

    public var body: some View {
        if let index = guide.walkthroughStep, index < guide.steps.count {
            GeometryReader { geo in
                let step = guide.steps[index]
                let hole = holeRect(step.anchor, in: geo)
                ZStack(alignment: .topLeading) {
                    SpotlightMask(hole: hole)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.35), value: hole)
                    callout(step, index: index, total: guide.steps.count)
                        .frame(width: 360)
                        .position(calloutPosition(for: step.anchor, hole: hole, in: geo.size))
                        .animation(.smooth(duration: 0.35), value: index)
                }
            }
            .onAppear { highlight(index) }
            .onChange(of: guide.walkthroughStep) { _, new in highlight(new) }
            .onDisappear { engine.foundControls = [] }
        }
    }

    private func highlight(_ index: Int?) {
        guard let index, index < guide.steps.count, let control = guide.steps[index].highlight else {
            engine.foundControls = []
            return
        }
        engine.foundControls = [control]
    }

    private func holeRect(_ anchor: SpotlightAnchor, in geo: GeometryProxy) -> CGRect {
        if let a = anchors[anchor] {
            return geo[a].insetBy(dx: -4, dy: -4)
        }
        // The toolbar lives in the title bar, above this view: open a sliver along the top edge.
        return CGRect(x: 0, y: -40, width: geo.size.width, height: 44)
    }

    private func calloutPosition(for anchor: SpotlightAnchor, hole: CGRect, in size: CGSize) -> CGPoint {
        switch anchor {
        case .map:
            // Over the inspector, so the whole drawing stays visible.
            return CGPoint(x: size.width - 196, y: size.height - 150)
        case .inspector:
            return CGPoint(x: max(196, hole.minX - 200), y: size.height - 150)
        case .toolbar:
            return CGPoint(x: size.width - 196, y: 130)
        }
    }

    private func callout(_ step: TourStep, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) of \(total)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(step.title)
                .font(.title3.weight(.semibold))
            Text(step.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let prompt = step.goal.prompt {
                HStack(spacing: 8) {
                    Image(systemName: guide.stepSatisfied ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                        .foregroundStyle(guide.stepSatisfied ? Color.green : Color.accentColor)
                        .symbolEffect(.pulse, isActive: !guide.stepSatisfied)
                        .contentTransition(.symbolEffect(.replace))
                    Text(guide.stepSatisfied ? "Nice." : "On the panel: \(prompt.lowercased())")
                        .font(.callout.weight(.medium))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            HStack {
                Button("End Tour") { guide.finishWalkthrough() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer()
                if index > 0 {
                    Button("Back") { guide.goToStep(index - 1) }
                }
                Button(index == total - 1 ? "Done" : (step.goal.prompt == nil ? "Next" : "Skip")) {
                    guide.goToStep(index + 1)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .modifier(CalloutBackground())
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

private struct CalloutBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct SpotlightMask: View {
    let hole: CGRect

    var body: some View {
        Canvas { ctx, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16), style: .continuous)
            ctx.fill(path, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        }
    }
}
