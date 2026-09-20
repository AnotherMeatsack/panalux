import SwiftUI

/// An illustrated, side-effect-free walkthrough: no photo or trail is touched.
struct IntroRewindWorkspaceDemo: View {
    let elapsed: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var phase: Int { min(3, max(0, Int(elapsed / 4))) }
    private let captions = [
        "Hover over the preview or click it. The larger workspace stays open.",
        "Select a source tangent to inspect it. Selecting alone does not change the photo.",
        "Check only the sliders you want to borrow. Leave the others untouched.",
        "Choose Merge. A new result combines your choices; both originals stay saved."
    ]
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Rewind+ · illustrated example", systemImage: "backward.end.fill").font(.title3.bold())
                Spacer()
                Label("Pinned open", systemImage: "pin.fill").foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                VStack(spacing: 18) {
                    node("Your current tangent", detail: "Contrast +11", symbol: "circle.fill", selected: false, color: .cyan)
                    node("Warm alternate", detail: "Exposure +0.35", symbol: "circle.fill", selected: phase >= 1, color: .purple)
                }
                VStack(spacing: 12) {
                    Image(systemName: "arrow.turn.up.right").foregroundStyle(.cyan)
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.purple)
                }.font(.title).opacity(phase >= 3 ? 1 : 0.15)
                node(phase >= 3 ? "New merged tangent" : "Your result", detail: phase >= 3 ? "Contrast +11 · Exposure +0.35" : "Created after Merge", symbol: "sparkles", selected: phase >= 3, color: .green)
                    .scaleEffect(phase >= 3 ? 1 : 0.94)
            }
            HStack(spacing: 18) {
                Label("Exposure +0.35", systemImage: phase >= 2 ? "checkmark.square.fill" : "square")
                    .foregroundStyle(phase >= 2 ? Color.cyan : .secondary)
                Label("Temperature", systemImage: "square").foregroundStyle(.secondary)
                Spacer()
                Text(phase >= 3 ? "Result created ✓" : "Merge Selected")
                    .fontWeight(.semibold).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(phase >= 2 ? Color.cyan.opacity(0.3) : Color.primary.opacity(0.08), in: Capsule())
            }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                ForEach(0..<4) { i in
                    Label(["Expand", "Inspect", "Choose sliders", "Merge"][i], systemImage: i < phase ? "checkmark.circle.fill" : "\(i + 1).circle.fill")
                        .foregroundStyle(i == phase ? Color.cyan : .secondary)
                    if i < 3 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                }
            }.font(.callout.bold())
            Text(captions[phase]).font(.system(size: 17, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center).frame(height: 48)
            Text("View This Tangent applies a source. Merge copies only checked sliders. Masks and crop are excluded.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 880)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18)))
            .scaleEffect(phase == 0 ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: phase)
    }
    private func node(_ title: String, detail: String, symbol: String, selected: Bool, color: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 5) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if selected { Image(systemName: "cursorarrow").foregroundStyle(color) }
        }.padding(18).frame(width: 330, height: 82)
            .background(color.opacity(selected ? 0.2 : 0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(selected ? 0.8 : 0.2), lineWidth: selected ? 2 : 1))
    }
}
