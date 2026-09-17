import SwiftUI

public struct QuickReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Reference")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Keep this beside you the first few sessions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Change a control", items: [
                        "Click it on the drawing, or touch it on the panel. the Map follows your hands.",
                        "Pick a command on the right, or drag a tile onto the drawing. Search covers every MIDI2LR command.",
                        "Keys have two jobs: On tap and While held.",
                        "⌘Z undoes map changes. Copy, Paste, and Swap sit above the command list."
                    ])
                    section("Factory modes", items: [
                        "Hold Up Shift. Color Mixer. Knobs 1–8 are the color bands; Reset Lift / Gamma / Gain pick hue, saturation, or luminance.",
                        "Hold User. Upright & Transform. Auto Color is Upright Auto.",
                        "Hold Viewer. Crop & Straighten. Knobs trim edges, the center ring straightens, Select opens the crop tool.",
                        "Hold Select. Cull. Grade-row keys rate, the center ring scrolls photos, the right ring zooms.",
                        "Tap or hold Cursor. Masks. Hold Add Node for the circular tool wheel. Spin a ring or roll a ball. Left ring (or Prev/Next Node and Frame) chooses New, Add, Subtract, or Intersect. Let go to create the mask, then place it with the mouse. Knobs grade that mask. Trackball placement is coming soon.",
                        "Tap Offset. Temp and Tint on the rings, global color on the right ball.",
                        "Hold Down Shift. Prev/Next Keyframe add photos to the selection.",
                        "Hold Wipe Still. compare with Before. Tap it for side-by-side.",
                        "More modes (Tone Curve, Detail, Effects, Lens, Presets) are in the Modes tiles. put them on any key."
                    ])
                    section("Hold vs. on", items: [
                        "HOLD in the notch readout means the mode ends when you let go.",
                        "ON means you tapped it on. Tap the same key again, or choose Back to Base.",
                        "While a mode is active, the keys it uses light up on the panel."
                    ])
                    section("Safety nets", items: [
                        "Safe Setup. knobs preview on screen without touching the photo. Held modes and keys still work.",
                        "Pause Output. nothing reaches Lightroom or Photoshop. The readout says what would have happened.",
                        "Back to Base. drops every mode and temporary setting. Also in the menu bar.",
                        "Your map is backed up at launch and before every import, preset, and reset (Settings → Maps)."
                    ])
                    section("Grab Still · Photoshop", items: [
                        "Select the frames in Lightroom and press Grab Still. They open as layers in Photoshop and auto-align.",
                        "Blend in Photoshop, then press Grab Still again. It flattens, saves, and returns to Lightroom."
                    ])
                    section("Notch HUD", items: [
                        "Slides out under the menu bar when you touch something and tucks away after 4 seconds.",
                        "Holding a mode shows all twelve knob names. the screens the panel doesn’t have.",
                        "Full, Minimal, or Hidden in Settings or the menu bar."
                    ])
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 640)
    }
    
    private func section(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .tracking(1.0)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Color.accentColor.opacity(0.8)).frame(width: 5, height: 5).padding(.top, 6)
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
