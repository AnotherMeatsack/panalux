import XCTest
import SwiftUI
@testable import PanaLux

/// Renders the intro and notch readout to PNGs for visual review.
/// Run with: PANALUX_RENDER_DIR=/some/folder swift test --filter RenderStillsTests
@MainActor
final class RenderStillsTests: XCTestCase {
    private var outDir: URL? {
        ProcessInfo.processInfo.environment["PANALUX_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func save<V: View>(_ view: V, size: CGSize, name: String) throws {
        guard let dir = outDir else { return }
        GlassCard.forceFallback = true
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("render failed: \(name)"); return
        }
        try png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    func testRenderIntro() throws {
        try XCTSkipIf(outDir == nil, "set PANALUX_RENDER_DIR to render")
        let moments: [Int: [Double]] = [0: [3], 1: [3], 2: [4], 3: [4], 4: [0.8, 2.0, 3.6, 5.2, 8.0], 5: [0.5, 1.5, 4.0, 6.5], 6: [0.4, 1.0, 2.5, 3.7, 4.9, 6.2], 7: [5], 8: [2]]
        for scene in 0..<9 {
            for t in moments[scene] ?? [3] {
                try save(IntroShowView.still(scene: scene, at: t), size: CGSize(width: 1180, height: 760),
                         name: String(format: "intro-%d-%04.1f", scene, t))
            }
        }
    }

    func testRenderReadouts() throws {
        try XCTSkipIf(outDir == nil, "set PANALUX_RENDER_DIR to render")
        let modes: [(String, ActiveDisplayMode)] = [
            ("knob", .knob(name: "Knob 4 · Contrast", param: "Contrast", value: 0.62, displayValue: "+24", isFine: false, angleDegrees: 20)),
            ("multi2", .multi([LiveReading(control: "Y_GAMMA", param: "Exposure", value: "+0.35 EV"),
                               LiveReading(control: "CONTRAST", param: "Contrast", value: "+12")])),
            ("multi5", .multi([LiveReading(control: "Y_GAMMA", param: "Exposure", value: "+0.35 EV"),
                               LiveReading(control: "CONTRAST", param: "Contrast", value: "+12"),
                               LiveReading(control: "TB_LIFT", param: "Shadows", value: "210° · 18%"),
                               LiveReading(control: "TB_GAMMA", param: "Midtones", value: "40° · 9%"),
                               LiveReading(control: "RING_GAIN", param: "Highlight Lum", value: "-6")])),
            ("action", .action(name: "AUTO_COLOR", label: "Auto Tone", phase: .sent))
        ]
        for (name, mode) in modes {
            let height = NotchHUDWindowController.height(for: mode)
            let view = readoutView(mode)
                .frame(width: 400, height: height)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.15)))
            try save(view, size: CGSize(width: 400, height: height), name: "hud-\(name)")
        }
        ToolWheelSession.shared.present(ownerLabel: "Add Node", index: 4, combine: .add)
        try save(ToolWheelView().background(Color(white: 0.12)), size: CGSize(width: 360, height: 360), name: "hud-mask-wheel")
        ToolWheelSession.shared.hide()
    }

    @ViewBuilder
    private func readoutView(_ mode: ActiveDisplayMode) -> some View {
        switch mode {
        case .knob(let n, let p, let v, let d, let f, let a):
            VirtualOLEDReadout(name: n, param: p, value: v, displayValue: d, isFine: f, angleDegrees: a)
        case .multi(let r):
            MultiReadout(readings: r)
        case .action(let n, let l, let ph):
            ButtonFlashView(name: n, label: l, phase: ph)
        default:
            EmptyView()
        }
    }
}

@MainActor
final class MapPageExportTests: XCTestCase {
    /// Writes the Map page with sample hover arrows, for checking in a browser.
    func testExportMapPage() throws {
        guard let dir = ProcessInfo.processInfo.environment["PANALUX_RENDER_DIR"].map(URL.init(fileURLWithPath:)) else {
            throw XCTSkip("set PANALUX_RENDER_DIR")
        }
        let svg = try XCTUnwrap(AppResources.string("micro-color-panel", "svg"))
        let profile = Profile.loadDefault()
        var loop = profile
        loop.buttons["LOOP"] = ButtonBinding(action: "WhiteBalanceAuto", holdProgram: .focused("PostCropVignetteMidpoint"))
        let cases: [(String, [String: [[String: String]]], String)] = [
            ("loop", MappingConnections.all(from: loop), "button_loop"),
            ("shift", MappingConnections.all(from: profile), "button_corner_upper_left"),
            ("viewer", MappingConnections.all(from: profile), "button_viewer")
        ]
        for (name, connections, hover) in cases {
            let json = String(data: try JSONSerialization.data(withJSONObject: connections), encoding: .utf8)!
            var html = InteractiveSVGView.pageHTML(svgContent: svg)
            html = html.replacingOccurrences(of: "</body>", with: """
            <script>
              window.setConnections(\(String(reflecting: json)));
              setTimeout(() => {
                const el = document.querySelector('[data-control-id="\(hover)"]');
                el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
              }, 300);
            </script>
            </body>
            """)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try html.write(to: dir.appendingPathComponent("map-\(name).html"), atomically: true, encoding: .utf8)
        }
    }
}
