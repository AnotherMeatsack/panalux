import Foundation

public enum MotionKind: String {
    case knob
    case trackball
    case ring
    case keyDown = "key_down"
    case keyUp = "key_up"
}

public struct PanelMotion: Identifiable {
    public let id = UUID()
    public let reportId: Int
    public let slot: Int          // Slot index or button bit index
    public let delta: Int         // Signed ticks
    public let kind: MotionKind
    
    public init(reportId: Int, slot: Int, delta: Int = 0, kind: MotionKind) {
        self.reportId = reportId
        self.slot = slot
        self.delta = delta
        self.kind = kind
    }
}

public class PanelDecoder {
    public static let encoderLSB: Int = 360
    
    private var heldButtonBits: Set<Int> = []
    
    public init() {}
    
    public func reset() {
        heldButtonBits.removeAll()
    }
    
    public func decode(reportId: UInt8, data: Data) -> [PanelMotion] {
        var motions: [PanelMotion] = []
        
        // IOKit usually prefixes the payload with the report ID. Never use
        // `data[0] == reportId` for report 0x02 — 0x02 is also a valid first
        // bitmap byte, and stripping it shifts every button by 8 bits so holds
        // flicker on/off.
        let payload = Self.stripReportID(reportId: reportId, data: data)
        
        switch reportId {
        case 0x02: // Buttons bitmap (8 bytes = 64 bits)
            guard payload.count >= 8 else { return [] }
            var currentBits = Set<Int>()
            for byteIndex in 0..<min(8, payload.count) {
                let byteVal = payload[byteIndex]
                for bit in 0..<8 {
                    if (byteVal & (1 << bit)) != 0 {
                        currentBits.insert(byteIndex * 8 + bit)
                    }
                }
            }
            
            // Newly pressed buttons
            let pressed = currentBits.subtracting(heldButtonBits)
            for b in pressed.sorted() {
                motions.append(PanelMotion(reportId: Int(reportId), slot: b, delta: 0, kind: .keyDown))
            }
            
            // Released buttons
            let released = heldButtonBits.subtracting(currentBits)
            for b in released.sorted() {
                motions.append(PanelMotion(reportId: Int(reportId), slot: b, delta: 0, kind: .keyUp))
            }
            heldButtonBits = currentBits
            
        case 0x05: // Trackballs & Rings (36 bytes = 9 x int32 LE)
            // Block 0: Lift (X=0, Y=1, Ring=2)
            // Block 1: Gamma (X=3, Y=4, Ring=5)
            // Block 2: Gain (X=6, Y=7, Ring=8)
            let count = min(9, payload.count / 4)
            for i in 0..<count {
                let offset = i * 4
                let val = payload.withUnsafeBytes { ptr -> Int32 in
                    ptr.load(fromByteOffset: offset, as: Int32.self)
                }
                if val != 0 {
                    let isRing = (i % 3 == 2)
                    motions.append(PanelMotion(
                        reportId: Int(reportId),
                        slot: i,
                        delta: Int(val),
                        kind: isRing ? .ring : .trackball
                    ))
                }
            }
            
        case 0x06: // Knobs (64 bytes = 16 x int32 LE, 12 knobs are slots 0-11)
            let count = min(16, payload.count / 4)
            for i in 0..<count {
                let offset = i * 4
                let val = payload.withUnsafeBytes { ptr -> Int32 in
                    ptr.load(fromByteOffset: offset, as: Int32.self)
                }
                if val != 0 {
                    motions.append(PanelMotion(
                        reportId: Int(reportId),
                        slot: i,
                        delta: Int(val),
                        kind: .knob
                    ))
                }
            }
            
        default:
            break
        }
        
        return motions
    }
    
    /// Report 0x02 is 8 bytes, 0x05 is 36, 0x06 is 64. A leading report-ID byte
    /// makes those 9 / 37 / 65.
    private static func stripReportID(reportId: UInt8, data: Data) -> Data {
        let expected: Int
        switch reportId {
        case 0x02: expected = 8
        case 0x05: expected = 36
        case 0x06: expected = 64
        default: expected = data.count
        }
        if data.count == expected + 1 {
            return data.subdata(in: 1..<data.count)
        }
        if data.count > expected && data.first == reportId {
            return data.subdata(in: 1..<data.count)
        }
        return data
    }
}
