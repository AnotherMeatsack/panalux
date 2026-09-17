import SwiftUI

public struct VirtualOLEDReadout: View {
    public let name: String
    public let param: String
    public let value: Double
    public let displayValue: String
    public let isFine: Bool
    public let angleDegrees: Double

    public init(name: String, param: String, value: Double, displayValue: String, isFine: Bool, angleDegrees: Double = 0) {
        self.name = name
        self.param = param
        self.value = value
        self.displayValue = displayValue
        self.isFine = isFine
        self.angleDegrees = angleDegrees
    }

    private var normalizedOffset: CGFloat {
        CGFloat((value - 0.5) * 2.0)
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                    .frame(width: 52, height: 52)
                if let img = PanelGlyph.image(named: "hud-knob") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(angleDegrees))
                } else {
                    Circle()
                        .fill(Color(red: 0.24, green: 0.27, blue: 0.30))
                        .overlay(Circle().stroke(Color(red: 0.48, green: 0.51, blue: 0.56), lineWidth: 1.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 2, height: 10)
                                .offset(y: -10)
                        )
                        .rotationEffect(.degrees(angleDegrees))
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
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
                    .lineLimit(1)

                GeometryReader { geo in
                    let w = geo.size.width
                    let midX = w / 2.0
                    let offset = normalizedOffset
                    let barW = abs(offset) * (w / 2.0)
                    let barX = offset >= 0 ? midX : midX - barW
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                        Rectangle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 2)
                            .position(x: midX, y: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: max(2, barW), height: 4)
                            .position(x: barX + barW / 2.0, y: 3)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .position(x: midX + offset * (w / 2.0 - 4), y: 3)
                    }
                }
                .frame(height: 6)
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
