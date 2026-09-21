import XCTest
import AppKit
@testable import PanaLux

final class ReferenceImageTests: XCTestCase {
    @MainActor
    func testCurrentDiagramRenders() async throws {
        let completed = expectation(description: "Current diagram")
        try PanelReference.current(StudioEngine.shared).peekHTML.write(toFile: "/tmp/panalux-peek-reference.html", atomically: true, encoding: .utf8)
        ReferenceImageExport.render(html: PanelReference.current(StudioEngine.shared).html, to: URL(fileURLWithPath: "/tmp/panalux-reference-current.png")) { error in
            XCTAssertNil(error)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 30)
    }

    @MainActor
    func testAllLayerOverviewRenders() async throws {
        let completed = expectation(description: "All layers")
        let url = URL(fileURLWithPath: "/tmp/panalux-reference-overview.png")
        let html = LayerReference.html(for: StudioEngine.shared)
        try html.write(toFile: "/tmp/panalux-overview-reference.html", atomically: true, encoding: .utf8)
        ReferenceImageExport.render(html: html, to: url) { error in
            XCTAssertNil(error)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    @MainActor
    func testActualReferenceCardRenders() async throws {
        let completed = expectation(description: "Actual map")
        let url = URL(fileURLWithPath: "/tmp/panalux-reference-actual.png")
        let html = ReferenceCard.html(for: StudioEngine.shared)
        try html.write(toFile: "/tmp/panalux-detailed-reference.html", atomically: true, encoding: .utf8)
        XCTAssertTrue(html.contains("Button combinations"))
        ReferenceImageExport.render(html: html, to: url) { error in
            XCTAssertNil(error)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    @MainActor
    func testReferencePNGIncludesFullDocument() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("panalux-reference-test.png")
        let completed = expectation(description: "Rendered reference")
        var failure: Error?
        ReferenceImageExport.render(html: "<html><body style='margin:0;background:white'><div style='height:1600px'>PanaLux reference</div><div style='height:200px;background:red'>Bottom of map</div></body></html>", to: url) { error in
            failure = error
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertNil(failure)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 1400)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 1800)
        let bottom = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 50)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(bottom.redComponent, 0.9)
        // Check the red sentinel survives below the initial viewport; color
        // management can shift its exact RGB channels on different displays.
        XCTAssertGreaterThan(bottom.redComponent - bottom.greenComponent, 0.5)
        XCTAssertGreaterThan(bottom.redComponent - bottom.blueComponent, 0.5)
    }
}
