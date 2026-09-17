import Foundation

public class PanelLEDController {
    public static func makeLedPayload(activeBits: Set<Int>) -> Data {
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
}
