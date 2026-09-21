import AppKit
import Foundation

/// A printable sheet of the current map. base plus every mode. Regenerated each time it opens.
public enum ReferenceCard {
    public static func open(overview: Bool = false) {
        let url = AppPaths.supportDir.appendingPathComponent(overview ? "All Layers Reference.html" : "Reference Card.html")
        do {
            try FileManager.default.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
            let content = overview ? LayerReference.html(for: StudioEngine.shared) : html(for: StudioEngine.shared)
            try content.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func html(for engine: StudioEngine) -> String {
        SVGPanelReference.document(states: SVGPanelReference.states(for: engine))
    }
}
