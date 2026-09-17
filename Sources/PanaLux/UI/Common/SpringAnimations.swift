import SwiftUI

public struct SpringPhysics {
    /// Notch readout expand/collapse spring
    public static let bubble = Animation.spring(response: 0.36, dampingFraction: 0.72, blendDuration: 0.15)
    
    /// Snappy micro-interaction spring for controls and buttons
    public static let micro = Animation.spring(response: 0.22, dampingFraction: 0.65)
    
    /// Smooth slow retract spring
    public static let retract = Animation.spring(response: 0.45, dampingFraction: 0.85)
}
