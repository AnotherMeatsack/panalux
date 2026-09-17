import SwiftUI

public struct HardwareCalibrationView: View {
    @ObservedObject var hwMap = HardwareMap.shared
    @ObservedObject var telemetry = HardwareTelemetry.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedControlKey: String = "SHIFT"
    @State private var isListeningForInput: Bool = false
    @State private var lastLearnedMessage: String? = nil
    
    private let commonKeysToCalibrate: [(name: String, label: String, description: String)] = [
        ("SHIFT", "Up Shift (Upper-Left Triangle)", "Held down for HSL Color Mixer layer"),
        ("CORNER_LOWER_RIGHT", "Down Shift (Lower-Right Triangle)", "Secondary shift / bank"),
        ("SELECT", "Select Button", "Center row select key"),
        ("USER", "User Button", "Hold for perspective/transform"),
        ("LOOP", "Loop Button", "Hold for fine precision (0.25x)"),
        ("AUTO_COLOR", "Auto Color", "Top-left button"),
        ("OFFSET", "Offset Button", "Toggles offset layer"),
        ("RESET_ALL", "Reset All", "Resets image adjustments")
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Learn Key Positions")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("If a key on your panel lights up the wrong control, teach PanaLux where it is.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(20)
            .background(Color(white: 0.1))
            
            Divider().background(Color.white.opacity(0.12))
            
            // Live Sniffer Telemetry Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isListeningForInput ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text("LIVE HARDWARE SNIFFER")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1.0)
                    Spacer()
                    if telemetry.timestamp != Date.distantPast {
                        Text("Active")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                HStack(spacing: 16) {
                    if let bit = telemetry.slotOrBit, let rid = telemetry.reportId {
                        HStack(spacing: 8) {
                            Text("Report 0x\(String(format: "%02X", rid))")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.cyan.opacity(0.15)))
                            
                            Text("Bit / Slot: \(bit)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                            
                            if let mappedName = hwMap.controlName(forButtonBit: bit) {
                                Text("Mapped: \(mappedName)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Text("Unmapped")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                    } else {
                        Text("Touch or press any physical button on your desk to inspect its raw code…")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            }
            .padding(20)
            
            Divider().background(Color.white.opacity(0.08))
            
            // Calibration List & Learn Button
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SELECT A KEY TO LEARN")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(1.0)
                    
                    ForEach(commonKeysToCalibrate, id: \.name) { item in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.label)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    if let currentBit = hwMap.buttonBit(forControl: item.name) {
                                        Text("Bit \(currentBit)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.cyan)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.cyan.opacity(0.15)))
                                    }
                                }
                                Text(item.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            if isListeningForInput && selectedControlKey == item.name {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Press Physical Key Now…")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                            } else {
                                Button("Learn Key") {
                                    selectedControlKey = item.name
                                    isListeningForInput = true
                                    lastLearnedMessage = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedControlKey == item.name ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
                        )
                    }
                    
                    if let msg = lastLearnedMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
                    }
                }
                .padding(20)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Footer: Reset to Defaults
            HStack {
                Button(action: {
                    hwMap.resetToDefaults()
                    lastLearnedMessage = "Hardware map reset to factory defaults."
                }) {
                    Label("Reset to Factory Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(white: 0.08))
        }
        .frame(width: 580, height: 560)
        .background(Color(white: 0.07))
        .onChange(of: telemetry.timestamp) { _, _ in
            guard isListeningForInput, let bit = telemetry.slotOrBit else { return }
            hwMap.mapButton(bit: bit, to: selectedControlKey)
            isListeningForInput = false
            lastLearnedMessage = "Successfully mapped Bit \(bit) to \(selectedControlKey)!"
        }
    }
}
