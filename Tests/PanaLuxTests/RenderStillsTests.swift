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
            ("action", .action(name: "AUTO_COLOR", label: "Auto Tone", phase: .sent)),
            ("hold-detail", .layerBanner(
                layer: "DETAIL", variant: nil, hint: "Sharpening and noise reduction",
                chips: ["12 knobs", "3 keys"], latched: false,
                grid: [
                    KnobCell(label: "Sharpen", value: "52", isOverlay: true),
                    KnobCell(label: "Radius", value: "1.2", isOverlay: true),
                    KnobCell(label: "Detail", value: "38", isOverlay: true),
                    KnobCell(label: "Masking", value: "14", isOverlay: true),
                    KnobCell(label: "Lum NR", value: "20", isOverlay: true),
                    KnobCell(label: "Lum Det", value: "50", isOverlay: true),
                    KnobCell(label: "Lum Con", value: "0", isOverlay: true),
                    KnobCell(label: "Color NR", value: "25", isOverlay: true),
                    KnobCell(label: "Exposure", value: "+0.35", isOverlay: false),
                    KnobCell(label: "Contrast", value: "+12", isOverlay: false),
                    KnobCell(label: "Temp", value: "5200 K", isOverlay: false),
                    KnobCell(label: "Blending", value: "50", isOverlay: false)
                ])),
            ("rewind-now", .rewind(RewindSamples.now)),
            ("rewind-scrubbing", .rewind(RewindSamples.scrubbing)),
            ("rewind-peeking", .rewind(RewindSamples.peeking)),
            ("rewind-branch", .rewind(RewindSamples.branched)),
            ("rewind-crowded", .rewind(RewindSamples.crowded)),
            ("rewind-playing", .rewind(RewindSamples.playing)),
            ("rewind-reverse", .rewind(RewindSamples.reversing))
        ]
        for (name, mode) in modes {
            let height = NotchHUDWindowController.height(for: mode)
            let view = readoutView(mode)
                .frame(width: 400, height: height)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.15)))
            try save(view, size: CGSize(width: 400, height: height), name: "hud-\(name)")
        }
        // Rewind: the notch while you scrub your own session.
        let detailKnobs: [KnobCell] = [
            KnobCell(label: "Blacks", value: "-12", isOverlay: false),
            KnobCell(label: "Exposure", value: "+0.35", isOverlay: true),
            KnobCell(label: "Whites", value: "+8", isOverlay: false),
            KnobCell(label: "Contrast", value: "+24", isOverlay: true),
            KnobCell(label: "Clarity", value: "+6", isOverlay: false),
            KnobCell(label: "Texture", value: "0", isOverlay: false),
            KnobCell(label: "Vibrance", value: "+14", isOverlay: true),
            KnobCell(label: "Shadows", value: "+31", isOverlay: true),
            KnobCell(label: "Highlight", value: "-46", isOverlay: true),
            KnobCell(label: "Sat", value: "+5", isOverlay: false),
            KnobCell(label: "Temp", value: "5450 K", isOverlay: true),
            KnobCell(label: "Blending", value: "50", isOverlay: false)
        ]
        var edits: [DesignTrailMark] = []
        for step in stride(from: 4.0, through: 268.0, by: 5.5) {
            edits.append(DesignTrailMark(ago: step, kind: .edit))
        }
        let designScrubbing = DesignRewindState(
            ago: 134, span: 280,
            marks: edits + [
                DesignTrailMark(ago: 246, kind: .keyframe("Opened")),
                DesignTrailMark(ago: 198, kind: .landmark("Auto Tone")),
                DesignTrailMark(ago: 150, kind: .keyframe("Mask added")),
                DesignTrailMark(ago: 96, kind: .mark),
                DesignTrailMark(ago: 52, kind: .landmark("Preset")),
            ],
            takeName: "Main", otherTakes: 0, editsBack: 47, knobs: detailKnobs)
        let designBranched = DesignRewindState(
            ago: 62, span: 280,
            marks: edits + [
                DesignTrailMark(ago: 246, kind: .keyframe("Opened")),
                DesignTrailMark(ago: 198, kind: .landmark("Auto Tone")),
                DesignTrailMark(ago: 150, kind: .keyframe("Mask added")),
                DesignTrailMark(ago: 134, kind: .fork(takes: 2)),
                DesignTrailMark(ago: 96, kind: .mark),
            ],
            takeName: "Take 3 · warmer", otherTakes: 2, editsBack: 19, knobs: detailKnobs)
        for (name, st) in [("rewind-design", designScrubbing), ("rewind-design-branch", designBranched)] {
            let v = DesignRewindView(state: st)
                .frame(width: 400, height: 152)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.13)))
            try save(v, size: CGSize(width: 400, height: 152), name: "hud-\(name)")
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
        case .layerBanner(let layer, let variant, let hint, let chips, let latched, let grid):
            LayerBannerView(layer: layer, variant: variant, hint: hint,
                            chips: chips, latched: latched, grid: grid)
        case .trackball(let n, let st, let f, let c):
            VectorscopeView(name: n, state: st, isFine: f, companion: c)
        case .ring(let n, let p, _, let d, let f, let a):
            RingReadout(name: n, param: p, displayValue: d, isFine: f, angleDegrees: a)
        
        case .rewind(let state):
            RewindView(state: state)
        case .idle:
            EmptyView()
        }
    }
}

/// Every state the Rewind readout can be in, so all of them can be rendered and looked at.
enum RewindSamples {
    static func knobs(rolledBack: Double) -> [RewindKnobValue] {
        let row: [(String, String, Double, String, String)] = [
            ("Y_LIFT", "Blacks", 0.46, "-8", "0"),
            ("Y_GAMMA", "Exposure", 0.62, "+1.20 EV", "+0.35 EV"),
            ("Y_GAIN", "Whites", 0.55, "+10", "+2"),
            ("CONTRAST", "Contrast", 0.68, "+36", "+11"),
            ("PIVOT", "Clarity", 0.52, "+4", "0"),
            ("MID_DETAIL", "Texture", 0.58, "+16", "+3"),
            ("COL_BOOST", "Vibrance", 0.71, "+42", "+9"),
            ("SHAD", "Shadows", 0.44, "-12", "-4"),
            ("HI_LIGHT", "Highs", 0.39, "-22", "-7"),
            ("SAT", "Sat", 0.5, "0", "0"),
            ("HUE", "Temp", 0.13, "8200 K", "5650 K"),
            ("LUM_MIX", "Blending", 0.5, "0", "0")
        ]
        return row.enumerated().map { index, entry in
            let (control, label, value, display, past) = entry
            let changed = Double(index) / 12.0 < rolledBack
            return RewindKnobValue(control: control, label: label,
                                   value: changed ? 0.5 + (value - 0.5) * 0.3 : value,
                                   display: changed ? past : display, isChanged: changed)
        }
    }

    static let marks: [TrailMark] = [
        TrailMark(id: "open", time: 0, label: "Opened", kind: .open),
        TrailMark(id: "wb", time: 26, label: "Auto White Balance", kind: .action),
        TrailMark(id: "mask", time: 58, label: "New Radial Mask", kind: .mask),
        TrailMark(id: "mark", time: 92, label: "Mark", kind: .mark),
        TrailMark(id: "crop", time: 140, label: "Crop", kind: .crop)
    ]

    static let now = RewindState(
        origin: 0, tip: 180, playhead: 180, window: 200,
        marks: marks, knobs: knobs(rolledBack: 0), branchName: nil,
        isPeeking: false, isAtTip: true, caption: "Now", speed: 0,
        stepNumber: 640, stepCount: 640
    )

    static let scrubbing = RewindState(
        origin: 0, tip: 180, playhead: 74, window: 200,
        marks: marks, knobs: knobs(rolledBack: 0.7), branchName: nil,
        isPeeking: false, isAtTip: false, caption: "Exposure +0.35 EV", speed: 0.75,
        stepNumber: 212, stepCount: 640
    )

    /// Watching the edits happen again, in slow motion.
    static let playing = RewindState(
        origin: 0, tip: 180, playhead: 96, window: 200,
        marks: marks, knobs: knobs(rolledBack: 0.5), branchName: nil,
        isPeeking: false, isAtTip: false, caption: "84 seconds back", speed: 0.1,
        rate: 0.25, isPlaying: true, stepNumber: 301, stepCount: 640
    )

    /// Undoing itself, fast.
    static let reversing = RewindState(
        origin: 0, tip: 180, playhead: 120, window: 200,
        marks: marks, knobs: knobs(rolledBack: 0.3), branchName: nil,
        isPeeking: false, isAtTip: false, caption: "a minute back", speed: 0.5,
        rate: 4, isPlaying: true, isReverse: true, stepNumber: 402, stepCount: 640
    )

    static let peeking = RewindState(
        origin: 0, tip: 180, playhead: 180, window: 200,
        marks: marks, knobs: knobs(rolledBack: 0), branchName: nil,
        isPeeking: true, isAtTip: false, caption: "Now (peek)", speed: 0,
        stepNumber: 640, stepCount: 640
    )

    static let branched = RewindState(
        origin: 0, tip: 210, playhead: 120, window: 200,
        marks: marks + [TrailMark(id: "fork", time: 92, label: "Take 2", kind: .branch, branchName: "Take 2")],
        knobs: knobs(rolledBack: 0.35), branchName: "Take 2",
        isPeeking: false, isAtTip: false, caption: "Take 2", speed: 0.2,
        stepNumber: 388, stepCount: 702
    )

    /// Four landmarks inside a few seconds. Their labels must not print on top of each other.
    static let crowded = RewindState(
        origin: 0, tip: 120, playhead: 66, window: 200,
        marks: [
            TrailMark(id: "a", time: 60, label: "New Radial Mask", kind: .mask),
            TrailMark(id: "b", time: 63, label: "Paste Settings", kind: .paste),
            TrailMark(id: "c", time: 66, label: "Mark", kind: .mark),
            TrailMark(id: "d", time: 70, label: "Crop", kind: .crop),
            TrailMark(id: "e", time: 74, label: "Take 3", kind: .branch, branchName: "Take 3")
        ],
        knobs: knobs(rolledBack: 0.5), branchName: nil,
        isPeeking: false, isAtTip: false, caption: "Mark", speed: 0.1
    )
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
