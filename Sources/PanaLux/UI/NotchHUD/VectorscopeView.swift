import SwiftUI

public struct VectorscopeView: View {
    public let name: String
    public let state: TrackballState
    public let isFine: Bool
    public let companion: String?
    
    public init(name: String, state: TrackballState, isFine: Bool, companion: String? = nil) {
        self.name = name
        self.state = state
        self.isFine = isFine
        self.companion = companion
    }
    
    private var cleanName: String {
        switch name {
        case "TB_LIFT": return "SHADOWS · LEFT BALL"
        case "TB_GAMMA": return "MIDTONES · CENTER BALL"
        case "TB_GAIN": return "HIGHLIGHTS · RIGHT BALL"
        default: return name.replacingOccurrences(of: "TB_", with: "").replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }
    
    private var hueDegrees: Int {
        Int((state.hueAngle * 360.0).rounded())
    }
    
    private var satPercent: Int {
        Int((state.saturation * 100.0).rounded())
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let img = PanelGlyph.image(named: "hud-ball") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                } else {
                    Circle()
                        .fill(Color(red: 0.14, green: 0.17, blue: 0.21))
                        .overlay(Circle().stroke(Color(red: 0.52, green: 0.57, blue: 0.63), lineWidth: 1.2))
                        .frame(width: 52, height: 52)
                }
                
                // Center of the ball — offset by how far you've rolled it.
                let posX = CGFloat(state.normalizedX) * 14.0
                let posY = CGFloat(-state.normalizedY) * 14.0
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.white.opacity(0.7), radius: 3)
                    .offset(x: posX, y: posY)
            }
            .frame(width: 52, height: 52)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cleanName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if isFine {
                        Text("FINE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
                HStack(spacing: 10) {
                    Text("HUE \(hueDegrees)°")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                    Text("SAT \(satPercent)%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .monospacedDigit()
                if let companion {
                    Text(companion)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
