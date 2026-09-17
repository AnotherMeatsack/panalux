import Foundation
import AppKit

/// Lightroom ↔ Photoshop round-trip driven from Grab Still.
///
/// In Lightroom: switch to Library, Photo → Edit In → Open as Layers, then Auto-Align.
/// In Photoshop: flatten, save (updates the catalog file), and return to Lightroom.
public class PhotoshopBridge {
    public static let shared = PhotoshopBridge()
    private let queue = DispatchQueue(label: "com.panalux.photoshop", qos: .userInitiated)
    private let busyLock = NSLock()
    private var isBusy = false
    
    private let lightroomBundleIds = [
        "com.adobe.LightroomClassicCC7",
        "com.adobe.Lightroom"
    ]
    private let handoffDir = (NSHomeDirectory() as NSString).appendingPathComponent("Pictures/Panel Handoff")
    private var sourceFolder: String?
    
    private init() {}
    
    public func executeAction(_ actionName: String, completion: @escaping (Result<String, Error>) -> Void) {
        busyLock.lock()
        if isBusy {
            busyLock.unlock()
            completion(.success("Still sending to Photoshop…"))
            return
        }
        isBusy = true
        busyLock.unlock()
        
        queue.async {
            defer {
                self.busyLock.lock()
                self.isBusy = false
                self.busyLock.unlock()
            }
            do {
                let message: String
                switch actionName {
                case "smart_roundtrip":
                    message = try self.smartRoundtrip()
                case "open_layers":
                    message = try self.sendAndAlign()
                default:
                    throw self.makeError(404, "Unknown Photoshop action: \(actionName)")
                }
                completion(.success(message))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func smartRoundtrip() throws -> String {
        let fromPhotoshop = isPhotoshopFrontmost()
        if fromPhotoshop {
            activatePhotoshop()
            Thread.sleep(forTimeInterval: 0.3)
            if jsDocumentCount() > 0 {
                let saved = try flattenAndSave()
                returnToDevelop()
                return saved
            }
            // Home screen after closing the stack: send the next frames.
            return try sendAndAlign()
        }
        return try sendAndAlign()
    }
    
    private func sendAndAlign() throws -> String {
        try sendStackOnce()
        if stackLooksLikeSinglePhotoGlitch() {
            closeActivePhotoshopDocument()
            Thread.sleep(forTimeInterval: 0.8)
            try sendStackOnce()
        }
        return "Sent to Photoshop"
    }

    private func sendStackOnce() throws {
        let before = photoshopDocumentWindowCount()
        try openAsLayers()
        _ = waitForNewDocument(before: before, timeout: 120)
    }

    /// First Open as Layers can land one photo while Photoshop is still launching.
    /// Close that leftover document and send the stack again.
    private func stackLooksLikeSinglePhotoGlitch() -> Bool {
        waitForLightroomIdle(timeout: 12)
        let end = Date().addingTimeInterval(10)
        while Date() < end {
            if jsLayerCount() >= 2 { return false }
            Thread.sleep(forTimeInterval: 1.2)
        }
        return jsDocumentCount() > 0 && jsLayerCount() < 2
    }

    private func waitForLightroomIdle(timeout: TimeInterval) {
        guard let lr = lightroomApp() else { return }
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if !LightroomAccessibility.isWorkingSheetVisible(pid: lr.processIdentifier) {
                Thread.sleep(forTimeInterval: 0.6)
                if !LightroomAccessibility.isWorkingSheetVisible(pid: lr.processIdentifier) { return }
            }
            _ = LightroomAccessibility.confirmLayersDialog(pid: lr.processIdentifier)
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    private func closeActivePhotoshopDocument() {
        _ = try? photoshopJS("""
        app.displayDialogs = DialogModes.NO;
        try { app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); } catch (e) {}
        'ok';
        """)
    }

    /// Accessibility window count — never AppleScript. `tell application` to Photoshop
    /// launches it and steals the menu bar, so Lightroom’s Photo menu disappears.
    private func photoshopDocumentWindowCount() -> Int {
        guard let ps = NSWorkspace.shared.runningApplications.first(where: isPhotoshop) else { return 0 }
        return LightroomAccessibility.namedWindowCount(
            pid: ps.processIdentifier,
            skippingTitles: ["adobe photoshop", "photoshop", "home"]
        )
    }

    private func openAsLayers() throws {
        guard let lr = lightroomApp() else {
            throw makeError(404, "Lightroom Classic isn’t running")
        }
        bringForward(lr)
        Thread.sleep(forTimeInterval: 0.85)
        try LightroomAccessibility.openAsLayers(pid: lr.processIdentifier)
    }

    private func waitForNewDocument(before: Int, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let lr = lightroomApp() {
                _ = LightroomAccessibility.confirmLayersDialog(pid: lr.processIdentifier)
            }
            if photoshopDocumentWindowCount() > before {
                return true
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        return false
    }
    
    /// After flatten+save, hide Photoshop’s home/new-doc screen and put Lightroom in front.
    /// Photoshop re-shows that screen after the last document closes, so we keep retrying
    /// and quit Photoshop if it is still sitting on the home screen.
    private func returnToDevelop() {
        let steps: [TimeInterval] = [0.0, 0.35, 0.85, 1.6, 2.5]
        var elapsed: TimeInterval = 0
        for (i, at) in steps.enumerated() {
            if at > elapsed {
                Thread.sleep(forTimeInterval: at - elapsed)
                elapsed = at
            }
            hidePhotoshop()
            activateLightroom()
            if i == 1, LightroomBridge.shared.isConnected {
                LightroomBridge.shared.fireAction("SwToMdevelop")
            }
            if i == 2, LightroomBridge.shared.isConnected {
                LightroomBridge.shared.fireAction("ShoVwdevelop_loupe")
            }
            if i >= 1, let lr = lightroomApp() {
                LightroomAccessibility.dismissNoSelectionDialog(pid: lr.processIdentifier)
            }
            if i == steps.count - 1, isPhotoshopFrontmost() {
                let docs = (try? photoshopJS("app.documents.length")).flatMap(Int.init) ?? -1
                if docs == 0 {
                    quitPhotoshop()
                    Thread.sleep(forTimeInterval: 0.45)
                    activateLightroom()
                }
            }
        }
    }
    
    private func alignLayers() throws -> String {
        let js = """
        var d = app.activeDocument;
        if (d.layers.length < 2) { "need at least 2 layers"; } else {
          var r = new ActionReference();
          r.putEnumerated(stringIDToTypeID("layer"), charIDToTypeID("Ordn"), stringIDToTypeID("targetEnum"));
          var s = new ActionDescriptor();
          s.putReference(charIDToTypeID("null"), r);
          executeAction(stringIDToTypeID("selectAllLayers"), s, DialogModes.NO);
          var r2 = new ActionReference();
          r2.putEnumerated(stringIDToTypeID("layer"), charIDToTypeID("Ordn"), stringIDToTypeID("targetEnum"));
          var a = new ActionDescriptor();
          a.putReference(charIDToTypeID("null"), r2);
          a.putEnumerated(stringIDToTypeID("using"), stringIDToTypeID("alignmentType"), stringIDToTypeID("auto"));
          a.putBoolean(stringIDToTypeID("vignette"), false);
          a.putBoolean(stringIDToTypeID("radialDistort"), false);
          executeAction(stringIDToTypeID("align"), a, DialogModes.NO);
          "Aligned " + d.layers.length + " layers";
        }
        """
        return try photoshopJS(js)
    }
    
    private func flattenAndSave() throws -> String {
        activatePhotoshop()
        Thread.sleep(forTimeInterval: 0.2)
        let probe = (try? photoshopJS(
            "app.displayDialogs=DialogModes.NO; if(app.documents.length<1){'0|';} else { var d=app.activeDocument; var p=''; try{p=d.fullName.fsName;}catch(e){p='';} d.layers.length + '|' + p; }"
        )) ?? ""
        let parts = probe.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let layerCount = Int(parts.first ?? "0") ?? 0
        let docPath = parts.count > 1 ? String(parts[1]) : ""
        let isRaw = !docPath.isEmpty && ![".tif", ".tiff", ".psd", ".psb", ".jpg", ".jpeg", ".png"].contains(where: {
            docPath.lowercased().hasSuffix($0)
        })
        if isRaw && layerCount <= 1 {
            return "\(URL(fileURLWithPath: docPath).lastPathComponent) is a single-layer RAW. open the layered blend first"
        }

        let fallback = sourceFolder ?? handoffDir
        try FileManager.default.createDirectory(atPath: fallback, withIntermediateDirectories: true)
        let stamp = Self.timestamp()
        let fallbackJS = fallback.replacingOccurrences(of: "\\", with: "/").replacingOccurrences(of: "\"", with: "")
        let js = """
        app.displayDialogs = DialogModes.NO;
        try {
          if (app.documents.length < 1) { throw "no document"; }
          var d = app.activeDocument;
          var folder = null, base = d.name.replace(/\\.[^.]+$/, "");
          try { folder = d.path.fsName; } catch (e) { folder = null; }
          var writable = false;
          try { writable = /\\.(psd|psb|tif|tiff|jpg|jpeg|png)$/i.test(d.fullName.fsName); } catch (e) { writable = false; }
          var o = new TiffSaveOptions();
          o.imageCompression = TIFFEncoding.TIFFLZW;
          o.layers = false;
          d.flatten();
          var out;
          try {
            if (writable) {
              d.save();
              out = d.fullName.fsName;
            } else {
              if (folder === null) { folder = "\(fallbackJS)"; }
              var f = new File(folder + "/" + base + "-blend-\(stamp).tif");
              d.saveAs(f, o, false, Extension.LOWERCASE);
              out = f.fsName;
            }
          } catch (eSave) {
            folder = "\(fallbackJS)";
            var f2 = new File(folder + "/" + base + "-blend-\(stamp).tif");
            d.saveAs(f2, o, true, Extension.LOWERCASE);
            out = f2.fsName;
          }
          try { d.close(SaveOptions.DONOTSAVECHANGES); } catch (e) {}
          out;
        } catch (e) { "ERR:" + e; }
        """
        let out = try photoshopJS(js)
        if out.hasPrefix("ERR:") {
            throw makeError(500, "Photoshop couldn’t save: \(out.dropFirst(4))")
        }
        return "Saved \(out)"
    }

    /// HUD-only. Do not call Photoshop JavaScript from the button-down path.
    public func isPhotoshopLikelyHoldingDocument() -> Bool {
        isPhotoshopFrontmost()
    }

    private func jsLayerCount() -> Int {
        (try? photoshopJS("var n=0; try{n=app.activeDocument.layers.length;}catch(e){n=0;} n")).flatMap(Int.init) ?? 0
    }

    private func jsDocumentCount() -> Int {
        (try? photoshopJS("app.documents.length")).flatMap(Int.init) ?? 0
    }
    
    private func isPhotoshopFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return isPhotoshop(app)
    }
    
    private func isPhotoshop(_ app: NSRunningApplication) -> Bool {
        let bid = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        return bid.contains("photoshop") || name.contains("photoshop")
    }
    
    private func lightroomApp() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let match = apps.first(where: { app in
            lightroomBundleIds.contains(app.bundleIdentifier ?? "")
        }) {
            return match
        }
        return apps.first { app in
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").lowercased()
            return bid.contains("lightroom") || name.contains("lightroom")
        }
    }
    
    private func activatePhotoshop() {
        guard let ps = NSWorkspace.shared.runningApplications.first(where: isPhotoshop) else { return }
        bringForward(ps)
        if let bid = ps.bundleIdentifier {
            _ = try? runAppleScript("tell application id \"\(bid)\" to activate")
        }
    }

    private func activateLightroom() {
        guard let lr = lightroomApp() else { return }
        bringForward(lr)
        if let bid = lr.bundleIdentifier {
            _ = try? runAppleScript("tell application id \"\(bid)\" to activate")
        }
    }

    private func hidePhotoshop() {
        guard let ps = NSWorkspace.shared.runningApplications.first(where: isPhotoshop) else { return }
        let apply = {
            _ = ps.hide()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.sync(execute: apply) }
        if let bid = ps.bundleIdentifier {
            _ = try? runAppleScript("""
            tell application "System Events"
              try
                set visible of (first process whose bundle identifier is "\(bid)") to false
              end try
            end tell
            """)
        }
    }

    private func quitPhotoshop() {
        guard let ps = NSWorkspace.shared.runningApplications.first(where: isPhotoshop) else { return }
        let apply = { _ = ps.terminate() }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.sync(execute: apply) }
    }

    /// macOS 14+ ignores activateIgnoringOtherApps. Yield first or Lightroom stays behind.
    /// Photoshop’s home screen can steal focus after the document closes. Callers retry.
    private func bringForward(_ app: NSRunningApplication) {
        let apply = {
            _ = app.unhide()
            NSApp.yieldActivation(to: app)
            _ = app.activate(from: NSRunningApplication.current)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }
    
    private func photoshopBundleId() -> String {
        if let running = NSWorkspace.shared.runningApplications.first(where: { isPhotoshop($0) })?.bundleIdentifier {
            return running
        }
        return "com.adobe.Photoshop"
    }
    
    private func photoshopJS(_ js: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcs-ps.js")
        try js.write(to: url, atomically: true, encoding: .utf8)
        let bundle = photoshopBundleId()
        let script = """
        set f to POSIX file "\(url.path)"
        set js to read f as «class utf8»
        tell application id "\(bundle)" to do javascript js
        """
        return try runAppleScript(script)
    }
    
    /// Run AppleScript in-process so TCC attributes it to this app, not `/usr/bin/osascript`.
    @discardableResult
    private func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw makeError(500, "Could not compile AppleScript")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String)
                ?? (error["NSAppleScriptErrorMessage"] as? String)
                ?? "AppleScript failed"
            throw makeError(500, humanizeAppleScript(msg))
        }
        return result.stringValue ?? ""
    }
    
    private func humanizeAppleScript(_ raw: String) -> String {
        if let range = raw.range(of: "execution error:", options: .caseInsensitive) {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw
    }
    
    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "PhotoshopBridge", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
    
    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
