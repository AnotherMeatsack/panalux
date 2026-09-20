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
                    section("Presses & Combinations", items: [
                        "Press any knob to reset the parameter it currently controls, including modes and masks. Commands without a reset are left alone.",
                        "Open Presses & Combinations in the inspector. Enable editing, hold buttons and press a target. Release everything, then drag or click a command. Done returns to normal output.",
                        "Or build the gesture with Add a held button and the Press picker. No hardware or two-handed mouse work required.",
                        "For a preset: hold Previous Still and press Lum Mix, then choose a Preset slot. Configure that slot in Lightroom’s plug-in options first.",
                        "Combinations take priority over mode keys. The most specific matching combination wins. Held buttons keep their existing hold behavior; their tap is suppressed after a combination.",
                        "What’s New in the menu bar or Settings shows the release history offline."
                    ])
                    section("Wheel resets", items: [
                        "Reset Lift = shadows; Reset Gamma = midtones; Reset Gain = highlights.",
                        "Press Reset alone to clear both ball color and ring luminance. Hold Up Shift + Reset for color only, or Down Shift + Reset for luminance only.",
                        "If you adjusted only the ring, Up Shift leaves that brightness unchanged. The Shift combinations can be customized in Presses & Combinations."
                    ])
                    section("Rewind+ with the mouse", items: [
                        "While holding Undo: right ring scrubs the timeline, left ring visits landmarks, center ring switches tangents. The old factory speed layout migrates; customized layouts are preserved.",
                        "Hold Undo to show the preview, then hover briefly or click it. Or choose Expand Rewind+ from the menu bar. The workspace stays open until Escape or Collapse.",
                        "Drag the timeline slider, play/pause, or step through edits. Select a node to inspect it; View This Tangent applies that version.",
                        "Select a source, check the desired sliders, then merge into a new result. Both sources stay saved. Mask and crop settings are excluded.",
                        "Delete an inactive leaf with confirmation. Undo Delete restores it during this photo session. Original, current and depended-on branches are protected.",
                        "Click inside first: Space plays/pauses, arrows step, Command-M merges checked sliders, Shift-Command-N creates a tangent, Command-Delete deletes an eligible selection."
                    ])
                    section("Map Library & Community", items: [
                        "Open from the menu bar or Settings. Save Current names your setup; Use switches to a saved setup with backup and Undo.",
                        "Preview a saved map, import a file, or browse Community. Click source controls or drag section headers to your result. Choose Whole control, Tap only or Hold only.",
                        "Highlights show staged changes. Inspect the before/after readout, review included modes, then Merge Selected. Save Current gives the result its own name. Calibration and personal settings stay yours.",
                        "Save Source to My Setups keeps a community map locally. Export & Share opens a public GitHub draft; attach the file and submit for review. Preset slots use your own Lightroom configuration.",
                        "Suggest a Feature opens a public GitHub draft with your idea and workflow. A GitHub account is required to submit; no automatic photo or diagnostic upload."
                    ])
                    section("Factory modes", items: [
                        "Hold Up Shift. Color Mixer. Knobs 1–8 are the color bands. Up Shift + Reset Lift / Gamma / Gain resets only that ball; Down Shift resets only its luminance. Remove those combinations to restore the original Mixer bank keys.",
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
                        "Blend in Photoshop, then press Grab Still again. It flattens, saves, and returns to Lightroom.",
                        "Auto-align can be turned off in Settings. Auto-Align Layers can also go on its own key."
                    ])
                    section("Gathering a bracket", items: [
                        "Arrow keys in Lightroom always collapse a selection to one photo, so scattered frames are gathered instead of selected.",
                        "Walk the filmstrip with Next and Previous. Tap Previous Still on each frame you want. Skip the ones you don’t.",
                        "The readout counts them. Tap Previous Still again on a frame to drop it.",
                        "Press Grab Still. Only the gathered frames open as layers, aligned, and the bracket empties.",
                        "Clear Bracket and Show Bracket can go on any key if you want them."
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
