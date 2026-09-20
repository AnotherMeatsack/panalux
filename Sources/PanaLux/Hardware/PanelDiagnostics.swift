import Foundation

/// Bounded local diagnostics for physical button/reset regressions. No photo IDs,
/// file names, typed text, or image data are recorded.
enum PanelDiagnostics {
    private static let queue = DispatchQueue(label: "PanaLux.panel-diagnostics")
    static func record(_ message: String) {
        guard !AppRuntime.isRenderingStills else { return }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        queue.async {
            let url = AppPaths.supportDir.appendingPathComponent("Panel Input.log")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               (attrs[.size] as? NSNumber)?.intValue ?? 0 > 200_000 {
                try? Data().write(to: url)
            }
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            guard let file = try? FileHandle(forWritingTo: url) else { return }
            defer { try? file.close() }
            do { try file.seekToEnd(); try file.write(contentsOf: Data(line.utf8)) } catch { }
        }
    }
}
