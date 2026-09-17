import SwiftUI
import AppKit

enum PanelGlyph {
    static func image(named name: String) -> NSImage? {
        guard let url = AppResources.url(name, "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }
}

/// Outer ring from the panel SVG, spinning with encoder ticks.
public struct RingReadout: View {
    public let name: String
    public let param: String
    public let displayValue: String
    public let isFine: Bool
    public let angleDegrees: Double

    public init(name: String, param: String, displayValue: String, isFine: Bool, angleDegrees: Double) {
        self.name = name
        self.param = param
        self.displayValue = displayValue
        self.isFine = isFine
        self.angleDegrees = angleDegrees
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.10))
                    .frame(width: 52, height: 52)
                if let img = PanelGlyph.image(named: "hud-ring") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(angleDegrees))
                        .animation(.linear(duration: 0.08), value: angleDegrees)
                } else {
                    Circle()
                        .stroke(Color(red: 0.19, green: 0.21, blue: 0.24), lineWidth: 8)
                        .frame(width: 44, height: 44)
                        .overlay(
                            ForEach(0..<12, id: \.self) { i in
                                Capsule()
                                    .fill(Color.white.opacity(i % 3 == 0 ? 0.7 : 0.28))
                                    .frame(width: 2, height: 5)
                                    .offset(y: -18)
                                    .rotationEffect(.degrees(Double(i) * 30 + angleDegrees))
                            }
                        )
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(param.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.interpolate)
                    if isFine {
                        Text("FINE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
                Text(name.replacingOccurrences(of: "_", with: " "))
                    .contentTransition(.interpolate)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            // Fixed width: "+9" → "+10" must not squeeze the name and bar beside it.
            Text(displayValue)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
