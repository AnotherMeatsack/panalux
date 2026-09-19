import SwiftUI
import AppKit

struct ControlHelpRow: Identifiable {
    let id: String
    let control: String
    let action: String
    let hold: String

    static func rows(profile: Profile) -> [ControlHelpRow] {
        let db = CommandDatabase.shared
        func label(_ value: String?) -> String { value.map { db.label(for: $0) } ?? "Not assigned" }
        var rows = PanelLayout.knobs.enumerated().map { i, id in
            ControlHelpRow(id: id, control: "Knob \(i + 1) · \(PanelLayout.label(forControl: id))", action: label(profile.knobs[id]?.param), hold: "")
        }
        rows += PanelLayout.rings.map { id in .init(id: id, control: PanelLayout.label(forControl: id), action: label(profile.rings[id]?.param), hold: "") }
        rows += PanelLayout.balls.map { id in
            let ball = profile.balls[id]
            let text = ball?.param.map { label($0) } ?? (ball.map { "\(label($0.hue)) · \(label($0.sat))" } ?? "Not assigned")
            return .init(id: id, control: PanelLayout.label(forControl: id), action: text, hold: "")
        }
        for group in PanelLayout.buttonGroups {
            for (id, title) in group.buttons {
                let b = profile.buttons[id] ?? ButtonBinding()
                var actions: [String] = []
                if let action = b.action ?? b.ps { actions.append(label(action)) }
                if let layer = b.layer { actions.append("Toggle \(LayerNames.defaultTitle(layer))") }
                if let layer = b.enter_layer { actions.append("Enter \(LayerNames.defaultTitle(layer))") }
                if let variant = b.set_variant { actions.append("Bank: \(variant)") }
                if let program = b.tapProgram { actions.append(program.summary) }
                var holds: [String] = []
                if let layer = b.hold_layer { holds.append(LayerNames.defaultTitle(layer)) }
                if b.hold_picker != nil { holds.append("Mask tool wheel") }
                if let action = b.hold_action { holds.append(label(action)) }
                if let program = b.holdProgram { holds.append(program.summary) }
                if b.modifier != nil { holds.append("Fine adjustment") }
                rows.append(.init(id: id, control: title, action: actions.isEmpty ? "Not assigned" : actions.joined(separator: " · "), hold: holds.joined(separator: " · ")))
            }
        }
        return rows
    }
}

struct ControlHelpView: View {
    @ObservedObject var engine = StudioEngine.shared
    @ObservedObject var picker = ToolWheelSession.shared
    var close: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your controls, right now").font(.title2.weight(.semibold))
                    Text(engine.statusMessage).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            if picker.isPresented {
                Text("Mask wheel: centre/right ring chooses the tool; left ring chooses New, Add, Subtract or Intersect. Release \(picker.ownerLabel) to apply.")
                    .font(.callout).padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            TextField("Find a control or command", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Text("CONTROL").frame(width: 170, alignment: .leading)
                Text("TURN / TAP").frame(maxWidth: .infinity, alignment: .leading)
                Text("WHILE HELD").frame(width: 170, alignment: .leading)
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ControlHelpRow.rows(profile: engine.currentHelpProfile()).filter {
                        query.isEmpty || "\($0.control) \($0.action) \($0.hold)".localizedCaseInsensitiveContains(query)
                    }) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.control).frame(width: 170, alignment: .leading)
                            Text(row.action).frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.hold.isEmpty ? "—" : row.hold).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                        }
                        .font(.system(size: 12)).padding(.vertical, 9)
                        .accessibilityElement(children: .combine)
                        Divider().opacity(0.5)
                    }
                }
            }
            Text("Follows your saved map and active modes. Open with ⌘? in PanaLux; Escape closes this window.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 680, height: 620)
    }
}

final class ControlHelpWindowController {
    static let shared = ControlHelpWindowController()
    private var panel: NSPanel?
    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "PanaLux · Your Controls"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: ControlHelpView { [weak panel] in panel?.orderOut(nil) })
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}
