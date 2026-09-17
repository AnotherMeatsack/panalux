import SwiftUI

/// Display names, symbols, and colors for panel modes (layers).
public enum LayerNames {
    public static func defaultTitle(_ layer: String) -> String {
        switch layer.uppercased() {
        case "MIXER": return "Color Mixer"
        case "TRANSFORM": return "Upright & Transform"
        case "OFFSET": return "Offset · Temp & Tint"
        case "MASK": return "Masks"
        case "MULTISELECT": return "Add to Selection"
        case "CROP": return "Crop & Straighten"
        case "CULL": return "Cull"
        case "TONE": return "Tone Curve"
        case "DETAIL": return "Detail"
        case "EFFECTS": return "Effects"
        case "LENS": return "Lens & Optics"
        case "PRESETS": return "Presets"
        case "FINE": return "Fine"
        case "FOCUS": return "Focus Dial"
        default: return layer.capitalized
        }
    }

    public static func symbol(_ layer: String) -> String {
        switch layer.uppercased() {
        case "MIXER": return "paintpalette.fill"
        case "TRANSFORM": return "perspective"
        case "OFFSET": return "circle.grid.cross.fill"
        case "MASK": return "lasso.and.sparkles"
        case "MULTISELECT": return "command"
        case "CROP": return "crop.rotate"
        case "CULL": return "star.leadinghalf.filled"
        case "TONE": return "chart.xyaxis.line"
        case "DETAIL": return "circle.dotted.and.circle"
        case "EFFECTS": return "camera.filters"
        case "LENS": return "camera.aperture"
        case "PRESETS": return "square.stack.3d.up.fill"
        case "FINE": return "scope"
        case "FOCUS": return "dial.medium.fill"
        default: return "square.3.layers.3d"
        }
    }

    public static func color(_ layer: String) -> Color {
        switch layer.uppercased() {
        case "MIXER": return Color(red: 0.77, green: 0.54, blue: 0.98)
        case "TRANSFORM": return Color(red: 0.30, green: 0.82, blue: 0.88)
        case "OFFSET": return Color(red: 0.40, green: 0.73, blue: 0.42)
        case "MASK": return Color(red: 1.00, green: 0.72, blue: 0.30)
        case "MULTISELECT": return Color(red: 0.45, green: 0.62, blue: 1.00)
        case "CROP": return Color(red: 0.98, green: 0.45, blue: 0.45)
        case "CULL": return Color(red: 1.00, green: 0.84, blue: 0.20)
        case "TONE": return Color(red: 0.85, green: 0.85, blue: 0.90)
        case "DETAIL": return Color(red: 0.55, green: 0.85, blue: 0.65)
        case "EFFECTS": return Color(red: 0.95, green: 0.55, blue: 0.80)
        case "LENS": return Color(red: 0.55, green: 0.75, blue: 1.00)
        case "PRESETS": return Color(red: 0.95, green: 0.65, blue: 0.35)
        case "FINE": return .yellow
        case "FOCUS": return .cyan
        default: return .orange
        }
    }

    /// Mixer bands get their color in the HUD grid.
    public static func bandColor(in label: String) -> Color? {
        let bands: [(String, Color)] = [
            ("Red", Color(red: 1.0, green: 0.23, blue: 0.19)),
            ("Orange", Color(red: 1.0, green: 0.58, blue: 0.0)),
            ("Yellow", Color(red: 1.0, green: 0.8, blue: 0.0)),
            ("Green", Color(red: 0.2, green: 0.78, blue: 0.35)),
            ("Aqua", Color(red: 0.2, green: 0.68, blue: 0.9)),
            ("Blue", Color(red: 0.0, green: 0.48, blue: 1.0)),
            ("Purple", Color(red: 0.69, green: 0.32, blue: 0.87)),
            ("Magenta", Color(red: 1.0, green: 0.18, blue: 0.33))
        ]
        return bands.first { label.hasSuffix($0.0) }?.1
    }
}
