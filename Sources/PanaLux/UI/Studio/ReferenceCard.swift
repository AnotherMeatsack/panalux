import AppKit
import Foundation

/// A printable sheet of the current map. base plus every mode. Regenerated each time it opens.
public enum ReferenceCard {
    public static func open() {
        let url = AppPaths.supportDir.appendingPathComponent("Reference Card.html")
        do {
            try FileManager.default.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
            try html(for: StudioEngine.shared).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func html(for engine: StudioEngine) -> String {
        let p = engine.profile
        let db = CommandDatabase.shared
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        func label(_ id: String?) -> String { id.map { esc(db.label(for: $0)) } ?? "<span class=dim>-</span>" }

        func tapText(_ b: ButtonBinding?) -> String {
            guard let b else { return "" }
            if let a = b.action { return label(a) }
            if let ps = b.ps { return label(ps) }
            if let l = b.layer { return "Toggle \(esc(engine.layerTitle(l)))" }
            if let v = b.set_variant { return "Bank: \(esc(v))" }
            if let prog = b.tapProgram { return esc(prog.summary) }
            return ""
        }
        func holdText(_ b: ButtonBinding?) -> String {
            guard let b else { return "" }
            if let l = b.hold_layer { return "<b>\(esc(engine.layerTitle(l)))</b>" }
            if b.hold_picker != nil { return "<b>Mask tool wheel</b>" }
            if b.modifier != nil { return "Fine" }
            if let a = b.hold_action {
                return a == MomentaryCommands.compareBefore ? "Compare Before" : label(a)
            }
            if let prog = b.holdProgram { return esc(prog.summary) }
            return ""
        }

        var out = """
        <!doctype html><html><head><meta charset="utf-8"><title>PanaLux Reference Card</title>
        <style>
        :root { color-scheme: light; }
        body { font: 12px -apple-system, "SF Pro Text", Helvetica, sans-serif; color: #111; margin: 28px; }
        h1 { font-size: 22px; margin: 0 0 2px; }
        h2 { font-size: 15px; margin: 22px 0 6px; display: flex; gap: 8px; align-items: baseline; }
        h2 small { font-weight: 400; color: #666; font-size: 11px; }
        .sub { color: #666; margin-bottom: 14px; }
        .row { display: grid; grid-template-columns: repeat(6, 1fr); gap: 4px; margin: 4px 0; }
        .row3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; margin: 4px 0; }
        .cell { border: 1px solid #ddd; border-radius: 6px; padding: 5px 7px; min-height: 30px; }
        .cell i { display: block; font-style: normal; color: #888; font-size: 9px; text-transform: uppercase; letter-spacing: .04em; }
        .over { border-color: #e39b2b; background: #fff6e8; }
        table { border-collapse: collapse; width: 100%; }
        td, th { text-align: left; padding: 3px 6px; border-bottom: 1px solid #eee; vertical-align: top; }
        th { color: #888; font-weight: 500; font-size: 10px; text-transform: uppercase; }
        .dim { color: #bbb; }
        .mode { break-inside: avoid; }
        footer { margin-top: 26px; color: #888; font-size: 10px; }
        @media print { body { margin: 10mm; } .noprint { display: none; } }
        </style></head><body>
        <div class="noprint" style="float:right"><button onclick="print()">Print…</button></div>
        <h1>PanaLux</h1>
        <div class="sub">Your map, \(esc(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))). Hold a key for its mode; tap a key marked “toggle” to keep a mode on.</div>
        <h2>Base</h2>
        <div class="row">
        """
        for (i, k) in PanelLayout.knobs.enumerated() {
            out += "<div class=cell><i>Knob \(i + 1)</i>\(label(p.knobs[k]?.param))</div>"
        }
        out += "</div><div class=row3>"
        for (ring, ball) in zip(PanelLayout.rings, PanelLayout.balls) {
            let ballText = p.balls[ball].map { "\(label($0.hue)) · \(label($0.sat))" } ?? label(nil)
            out += "<div class=cell><i>\(esc(PanelLayout.shortLabel(forControl: ball)))</i>\(ballText)<i style='margin-top:4px'>\(esc(PanelLayout.shortLabel(forControl: ring)))</i>\(label(p.rings[ring]?.param))</div>"
        }
        out += "</div><table><tr><th>Key</th><th>Tap</th><th>Hold</th></tr>"
        for group in PanelLayout.buttonGroups {
            for (id, name) in group.buttons {
                let b = p.buttons[id]
                let tap = tapText(b), hold = holdText(b)
                guard !(tap.isEmpty && hold.isEmpty) else { continue }
                out += "<tr><td>\(esc(name))</td><td>\(tap)</td><td>\(hold)</td></tr>"
            }
        }
        out += "</table>"

        for (name, layer) in p.layers.sorted(by: { engine.layerTitle($0.key) < engine.layerTitle($1.key) }) {
            let entry = p.buttons.compactMap { key, b -> String? in
                if b.hold_layer == name && b.layer == name { return "hold or toggle \(PanelLayout.label(forControl: key))" }
                if b.hold_layer == name { return "hold \(PanelLayout.label(forControl: key))" }
                if b.layer == name { return "toggle \(PanelLayout.label(forControl: key))" }
                if b.enter_layer == name { return "\(PanelLayout.label(forControl: key)) turns it on" }
                return nil
            }.sorted().joined(separator: ", ")
            out += "<div class=mode><h2>\(esc(engine.layerTitle(name))) <small>\(esc(entry.isEmpty ? "not on a key yet. assign it in Map" : entry))</small></h2>"
            let variant = layer.default_variant
            let grid = engine.knobGrid(forLayer: name, variant: variant)
            if !grid.isEmpty {
                out += "<div class=row>"
                for (i, cell) in grid.enumerated() {
                    out += "<div class='cell\(cell.isOverlay ? " over" : "")'><i>Knob \(i + 1)</i>\(cell.isOverlay ? esc(cell.label) : "<span class=dim>\(esc(cell.label))</span>")</div>"
                }
                out += "</div>"
            }
            var rows: [String] = []
            for ring in PanelLayout.rings {
                if let r = layer.rings?[ring] { rows.append("<tr><td>\(esc(PanelLayout.shortLabel(forControl: ring)))</td><td>\(label(r.param))</td></tr>") }
            }
            for ball in PanelLayout.balls {
                if let b = layer.balls?[ball] { rows.append("<tr><td>\(esc(PanelLayout.shortLabel(forControl: ball)))</td><td>\(label(b.hue)) · \(label(b.sat))</td></tr>") }
            }
            for group in PanelLayout.buttonGroups {
                for (id, keyName) in group.buttons {
                    if let b = layer.buttons?[id] { rows.append("<tr><td>\(esc(keyName))</td><td>\(tapText(b))</td></tr>") }
                }
            }
            if let variants = layer.variants, !variants.isEmpty {
                rows.append("<tr><td>Banks</td><td>\(esc(variants.keys.sorted().joined(separator: " · ")))</td></tr>")
            }
            if !rows.isEmpty { out += "<table>" + rows.joined() + "</table>" }
            out += "</div>"
        }

        out += """
        <footer>PanaLux is a free, unofficial, open-source macOS app. It is not affiliated with, endorsed by, or related to Blackmagic Design, Adobe, or Apple.</footer>
        </body></html>
        """
        return out
    }
}
