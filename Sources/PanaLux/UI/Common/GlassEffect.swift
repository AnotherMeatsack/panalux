import SwiftUI
import AppKit

/// Real-time macOS WindowServer backdrop blur using native NSVisualEffectView
public struct VisualEffectViewRepresentable: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var cornerRadius: CGFloat
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        cornerRadius: CGFloat = 22
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.cornerRadius = cornerRadius
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
    }
}

public struct GlassBackgroundModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var specularAlpha: Double
    
    public init(cornerRadius: CGFloat = 22, specularAlpha: Double = 0.35) {
        self.cornerRadius = cornerRadius
        self.specularAlpha = specularAlpha
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Native macOS GPU backdrop blur (frosted glass)
                    VisualEffectViewRepresentable(
                        material: .hudWindow,
                        blendingMode: .behindWindow,
                        state: .active,
                        cornerRadius: cornerRadius
                    )
                    
                    // 2. High-contrast translucent dark obsidian tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                    
                    // 3. Apple-grade beveled specular edge reflection
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(specularAlpha),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02),
                                    Color.black.opacity(0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.50), radius: 20, x: 0, y: 8)
            )
    }
}

public extension View {
    func glassmorphism(cornerRadius: CGFloat = 22, specularAlpha: Double = 0.35) -> some View {
        self.modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, specularAlpha: specularAlpha))
    }
}

