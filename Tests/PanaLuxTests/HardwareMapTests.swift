import XCTest
@testable import PanaLux

final class HardwareMapTests: XCTestCase {
    private let navigation = [41: "PREV_KEYFRM", 42: "NEXT_KEYFRM", 45: "PREV_FRAME", 46: "NEXT_FRAME", 47: "PREV_CLIP", 48: "NEXT_CLIP"]
    private let legacy = ["41": "PREV_FRAME", "42": "NEXT_FRAME", "45": "PREV_CLIP", "46": "NEXT_CLIP", "47": "PREV_KEYFRM", "48": "NEXT_KEYFRM"]

    func testPhysicalNavigationReportsAndLEDReverseMap() {
        let map = HardwareMap(customMapURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let decoder = PanelDecoder()
        for (bit, name) in navigation {
            var report = Data(repeating: 0, count: 8)
            report[bit / 8] = UInt8(1 << (bit % 8))
            let down = decoder.decode(reportId: 2, data: report)
            XCTAssertEqual(down.count, 1)
            XCTAssertEqual(down.first?.kind, .keyDown)
            XCTAssertEqual(down.first.flatMap { map.controlName(forButtonBit: $0.slot) }, name)
            XCTAssertEqual(map.buttonBit(forControl: name), bit)
            let up = decoder.decode(reportId: 2, data: Data(repeating: 0, count: 8))
            XCTAssertEqual(up.first?.slot, bit)
            XCTAssertEqual(up.first?.kind, .keyUp)
        }
    }

    func testSavedFactoryCalibrationAndImportedMapsMigrate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var saved = legacy
        saved["12"] = "MY_CUSTOM_CONTROL"
        try JSONEncoder().encode(saved).write(to: url)
        let map = HardwareMap(customMapURL: url)
        for (bit, name) in navigation { XCTAssertEqual(map.controlName(forButtonBit: bit), name) }
        XCTAssertEqual(map.controlName(forButtonBit: 12), "MY_CUSTOM_CONTROL")
        map.applyShared(saved)
        let reloaded = HardwareMap(customMapURL: url)
        for (bit, name) in navigation { XCTAssertEqual(reloaded.controlName(forButtonBit: bit), name) }
    }

    func testCustomAndPartialCalibrationArePreserved() {
        var custom = legacy
        custom["41"] = "CUSTOM"
        XCTAssertEqual(HardwareMap.correctLegacyNavigation(custom), custom)
        custom.removeValue(forKey: "41")
        XCTAssertEqual(HardwareMap.correctLegacyNavigation(custom), custom)
        let corrected = HardwareMap.correctLegacyNavigation(legacy)
        XCTAssertEqual(HardwareMap.correctLegacyNavigation(corrected), corrected)
    }
}
