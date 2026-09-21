import Foundation

public enum PanelColorLED: Int, CaseIterable, Sendable {
    case bypassRed = 0
    case offsetGreen = 2
    case disableRed = 3
    case shiftUpGreen = 4
    case shiftDownGreen = 5
    case playStillGreen = 6
    case wipeStillGreen = 7
    case hliteGreen = 8
    case viewerGreen = 9
    case cursorGreen = 10
    
    public var controlName: String {
        switch self {
        case .bypassRed: return "BYPASS"
        case .offsetGreen: return "OFFSET"
        case .disableRed: return "DISABLE"
        case .shiftUpGreen: return "SHIFT"
        case .shiftDownGreen: return "CORNER_LOWER_RIGHT"
        case .playStillGreen: return "PLAY_STILL"
        case .wipeStillGreen: return "WIPE_STILL"
        case .hliteGreen: return "H/LITE"
        case .viewerGreen: return "VIEWER"
        case .cursorGreen: return "CURSOR"
        }
    }
    
    public var isRed: Bool {
        self == .bypassRed || self == .disableRed
    }
    
    public var isGreen: Bool {
        !isRed
    }
}

public class PanelLEDController {
    /// Report 0x02: 64 one-bit channels for bright-white button highlights.
    public static func makeLedPayload(activeBits: Set<Int>) -> Data {
        makeWhitePayload(activeBits: activeBits)
    }

    public static func makeWhitePayload(activeBits: Set<Int>) -> Data {
        var bytes = [UInt8](repeating: 0, count: 9)
        bytes[0] = 0x02 // Report ID
        for bit in activeBits {
            if bit >= 0 && bit < 64 {
                let byteIdx = 1 + (bit / 8)
                let bitIdx = bit % 8
                bytes[byteIdx] |= (1 << bitIdx)
            }
        }
        return Data(bytes)
    }

    /// Report 0x04: 48 one-bit channels for hardware color indicators (Red/Green).
    public static func makeColorPayload(activeBits: Set<Int>) -> Data {
        var bytes = [UInt8](repeating: 0, count: 7)
        bytes[0] = 0x04 // Report ID
        for bit in activeBits {
            if bit >= 0 && bit < 48 {
                let byteIdx = 1 + (bit / 8)
                let bitIdx = bit % 8
                bytes[byteIdx] |= (1 << bitIdx)
            }
        }
        return Data(bytes)
    }
    
    public static func colorChannel(forControl control: String) -> PanelColorLED? {
        PanelColorLED.allCases.first { $0.controlName == control }
    }
    
    public static func colorBit(forControl control: String) -> Int? {
        colorChannel(forControl: control)?.rawValue
    }
}
