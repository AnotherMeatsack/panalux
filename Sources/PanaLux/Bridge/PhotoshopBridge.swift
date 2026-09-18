import Foundation
import AppKit

/// Lightroom ↔ Photoshop round-trip driven from Grab Still.
///
/// Out: Photo → Edit In → Open as Layers, then auto-align once the stack lands.
/// Back: flatten, save, and return to Lightroom.
///
/// Which of the two a press means is decided by `phase`, not by which app happens
/// to be in front. Asking the frontmost app meant that pressing Grab Still from
/// the PanaLux window, or with Lightroom on a second display, sent a second stack
/// instead of saving the one already open.
public class PhotoshopBridge {
    public static let shared = PhotoshopBridge()
    private let queue = DispatchQueue(label: "com.panalux.photoshop", qos: .userInitiated)
    private let watchQueue = DispatchQueue(label: "com.panalux.photoshop.watch", qos: .utility)
    private let busyLock = NSLock()
    private var isBusy = false

    public enum Phase: Equatable {
        /// Nothing out at Photoshop. A press sends.
        case idle
        /// Lightroom is still handing files over. A press waits.
        case sending
        /// The stack is open and aligned. A press flattens, saves, and comes home.
        case blending
    }

    private var phaseValue: Phase = .idle
    private var sendStartedAt: Date = .distantPast
    /// How many layers this send should produce, from Lightroom's own selection count.
    /// Without it there is no way to tell a short stack from a finished one, which is
    /// why a stack that quietly arrived incomplete had to be spotted and resent by hand.
    private var expectedLayers: Int = 0
    private var resentForShortStack = false
    /// After this long, a press means the stack has landed and Lightroom is stuck on
    /// some unrelated dialog. Saving beats being told to wait forever.
    private let sendingGiveUp: TimeInterval = 30
    public private(set) var phase: Phase {
        get { busyLock.lock(); defer { busyLock.unlock() }; return phaseValue }
        set { busyLock.lock(); phaseValue = newValue; busyLock.unlock() }
    }

    /// Late news the HUD should show: the align finishing, or the stack failing to land.
    public var onProgress: ((String) -> Void)?

    /// Auto-align the stack after Open as Layers. Off means align it yourself.
    public var autoAlign: Bool = true

    private func report(_ message: String) {
        DispatchQueue.main.async { self.onProgress?(message) }
    }
    
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
            completion(.success("Still working…"))
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
                    message = try self.smartRoundtrip(fromBracket: false)
                case "bracket_roundtrip":
                    message = try self.smartRoundtrip(fromBracket: true)
                case "open_layers":
                    message = try self.sendStack(fromBracket: false)
                case "align_layers":
                    guard self.phase != .sending else {
                        completion(.success("Still sending to Photoshop…"))
                        return
                    }
                    message = try self.alignLayers()
                default:
                    throw self.makeError(404, "Unknown Photoshop action: \(actionName)")
                }
                completion(.success(message))
            } catch {
                self.log("FAIL  \(actionName): \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    private func smartRoundtrip(fromBracket: Bool) throws -> String {
        switch phase {
        case .sending:
            // Lightroom is mid-copy. Talking to Photoshop now steals the Photo menu
            // and can abort the stack, so normally say so and leave it alone.
            guard Date().timeIntervalSince(sendStartedAt) > sendingGiveUp else {
                return "Still sending to Photoshop…"
            }
            // Long enough that the watcher is stuck on something else. Save if there
            // is anything to save, rather than leaving the key dead.
            if jsDocumentCount() > 0 {
                let saved = try flattenAndSave()
                phase = .idle
                returnToDevelop()
                return saved
            }
            phase = .idle
            return try sendStack(fromBracket: fromBracket)

        case .blending:
            if jsDocumentCount() > 0 {
                let saved = try flattenAndSave()
                phase = .idle
                returnToDevelop()
                return saved
            }
            // The document was closed by hand. Fall through and send a new stack.
            phase = .idle
            return try sendStack(fromBracket: fromBracket)

        case .idle:
            // A document opened by hand still saves, so the key is never a dead end.
            if isPhotoshopFrontmost(), jsDocumentCount() > 0 {
                let saved = try flattenAndSave()
                returnToDevelop()
                return saved
            }
            return try sendStack(fromBracket: fromBracket)
        }
    }

    /// Click Open as Layers and return. Lightroom keeps copying in the background,
    /// so nothing here may talk to Photoshop — AppleScript steals the Photo menu and
    /// can abort a stack that is still arriving. The watcher picks it up from there.
    private func sendStack(fromBracket: Bool) throws -> String {
        guard let lr = lightroomApp() else {
            throw makeError(404, "Lightroom Classic isn’t running")
        }
        // Read the count before touching menus: activating Lightroom and walking its
        // menu bar is exactly when a selection can change underneath us.
        expectedLayers = LightroomBridge.shared.selectedPhotoCount ?? 0
        let module = LightroomBridge.shared.currentModule ?? "unreported"
        let trusted = LightroomAccessibility.isTrusted(prompt: false)
        log("SEND  selected=\(expectedLayers)  module=\(module)  bracket=\(fromBracket)  accessibility=\(trusted)")
        guard trusted else {
            throw makeError(403, "PanaLux has lost Accessibility permission. System Settings → Privacy & Security → Accessibility: switch PanaLux off and on again.")
        }
        if fromBracket {
            try showBracket(pid: lr.processIdentifier)
        }
        try openAsLayers()
        for _ in 0..<6 {
            _ = LightroomAccessibility.confirmLayersDialog(pid: lr.processIdentifier)
            Thread.sleep(forTimeInterval: 0.2)
        }
        sendStartedAt = Date()
        phase = .sending
        watchForStack(cameFromBracket: fromBracket)
        let n = expectedLayers
        if fromBracket { return "Sending the bracket to Photoshop…" }
        return n > 1 ? "Sending \(n) photos to Photoshop…" : "Sending to Photoshop…"
    }

    /// Show the Quick Collection and select all of it, so Open as Layers picks up
    /// exactly the photos that were gathered — skipped frames and all.
    private func showBracket(pid: pid_t) throws {
        bringForward(NSRunningApplication(processIdentifier: pid) ?? NSRunningApplication.current)
        Thread.sleep(forTimeInterval: 0.4)
        let shown = LightroomAccessibility.pressMenuItem(
            pid: pid, titles: ["Show Quick Collection", "Quick Collection"], menus: ["File", "Library"]
        ) || LightroomKeys.press("b", flags: [.maskCommand])
        guard shown else {
            throw makeError(403, "Couldn’t open the Quick Collection. Allow PanaLux in Privacy & Security → Accessibility.")
        }
        Thread.sleep(forTimeInterval: 0.7)
        _ = LightroomAccessibility.pressMenuItem(pid: pid, titles: ["Select All"], menus: ["Edit"])
            || LightroomKeys.press("a", flags: [.maskCommand])
        Thread.sleep(forTimeInterval: 0.4)
    }

    /// Wait for Lightroom to finish copying, wait for the stack to stop growing in
    /// Photoshop, then auto-align it once. All of the Lightroom-side waiting uses
    /// Accessibility only; Photoshop is not spoken to until Lightroom is done.
    private func watchForStack(cameFromBracket: Bool) {
        watchQueue.async {
            let idleStart = Date()
            guard self.waitForLightroomIdle(timeout: 240) else {
                self.phase = .blending
                self.log("WAIT  Lightroom never went idle after \(Int(Date().timeIntervalSince(idleStart)))s")
                self.report("Lightroom is still working. Press Grab Still again when the stack is open.")
                return
            }
            self.log("WAIT  Lightroom idle after \(String(format: "%.1f", Date().timeIntervalSince(idleStart)))s")
            guard let layers = self.waitForStableStack(timeout: 120), layers > 0 else {
                self.phase = .blending
                self.log("RESULT no stack seen in Photoshop; docs=\(self.jsDocumentCount()) \(self.describeDocument())")
                self.report("Couldn’t see the stack in Photoshop. Align it yourself, then press Grab Still to save.")
                return
            }
            self.log("RESULT \(layers) layer(s), expected \(self.expectedLayers)  \(self.describeDocument())")

            // A short stack. This is caught before anything has been blended — the stack
            // has only just landed and PanaLux has not said it is ready — so closing it
            // and sending again cannot throw work away.
            if self.expectedLayers > 1, layers < self.expectedLayers, !self.resentForShortStack {
                self.resentForShortStack = true
                self.report("Only \(layers) of \(self.expectedLayers) arrived. Sending again…")
                self.closeActivePhotoshopDocument()
                Thread.sleep(forTimeInterval: 1.2)
                if (try? self.sendStack(fromBracket: cameFromBracket)) != nil { return }
                self.phase = .blending
                self.log("resend failed")
                self.report("Only \(layers) of \(self.expectedLayers) arrived and the resend failed.")
                return
            }

            self.phase = .blending
            self.resentForShortStack = false
            if self.expectedLayers > 1, layers < self.expectedLayers {
                self.log("still short after a resend")
                self.report("\(layers) of \(self.expectedLayers) photos arrived. Close the document and press Grab Still to try again.")
                return
            }
            if cameFromBracket, let lr = self.lightroomApp() {
                _ = LightroomAccessibility.pressMenuItem(
                    pid: lr.processIdentifier, titles: ["Clear Quick Collection"], menus: ["File", "Library"]
                )
            }
            guard self.autoAlign, layers >= 2 else {
                self.report("Opened \(layers) layer\(layers == 1 ? "" : "s")")
                return
            }
            do {
                self.report(try self.alignLayers())
            } catch {
                self.report("Opened \(layers) layers. Auto-align didn’t run.")
            }
        }
    }

    /// True once Lightroom has had no sheet or progress bar for two checks running.
    private func waitForLightroomIdle(timeout: TimeInterval) -> Bool {
        guard let lr = lightroomApp() else { return false }
        let pid = lr.processIdentifier
        let end = Date().addingTimeInterval(timeout)
        // Give Lightroom a moment to put its progress bar up before believing it is idle.
        Thread.sleep(forTimeInterval: 1.5)
        while Date() < end {
            if !LightroomAccessibility.isWorkingSheetVisible(pid: pid) {
                Thread.sleep(forTimeInterval: 0.8)
                if !LightroomAccessibility.isWorkingSheetVisible(pid: pid) { return true }
            }
            _ = LightroomAccessibility.confirmLayersDialog(pid: pid)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// Layer count that has stopped changing: the stack has finished arriving.
    private func waitForStableStack(timeout: TimeInterval) -> Int? {
        let end = Date().addingTimeInterval(timeout)
        var previous = -1
        var stableRuns = 0
        while Date() < end {
            let count = jsLayerCount()
            if count > 0 && count == previous {
                stableRuns += 1
                if stableRuns >= 2 { return count }
            } else {
                stableRuns = 0
            }
            previous = count
            Thread.sleep(forTimeInterval: 1.2)
        }
        return previous > 0 ? previous : nil
    }

    /// Select every layer and auto-align. This is what lines the brackets up.
    @discardableResult
    private func alignLayers() throws -> String {
        let js = """
        app.displayDialogs = DialogModes.NO;
        var out;
        try {
          if (app.documents.length < 1) { out = "ERR:no document"; }
          else {
            var d = app.activeDocument;
            if (d.layers.length < 2) { out = "ERR:needs at least 2 layers"; }
            else {
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
              out = "Aligned " + d.layers.length + " layers";
            }
          }
        } catch (e) { out = "ERR:" + e; }
        out;
        """
        let result = try photoshopJS(js)
        if result.hasPrefix("ERR:") {
            throw makeError(500, "Auto-align: \(result.dropFirst(4))")
        }
        return result
    }

    private func closeActivePhotoshopDocument() {
        _ = try? photoshopJS(
            "app.displayDialogs = DialogModes.NO; "
            + "try { app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); } catch (e) {} 'ok';"
        )
    }

    /// A running account of every round-trip, so a stack that arrives short leaves
    /// evidence instead of only a memory of it having gone wrong again.
    private func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp)  \(line)\n".data(using: .utf8) else { return }
        let url = AppPaths.supportDir.appendingPathComponent("Photoshop Handoff.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    /// Names the open document, so the log shows whether Lightroom sent a layered stack
    /// or opened a single raw file through the wrong menu item.
    private func describeDocument() -> String {
        let probe = (try? photoshopJS(
            "var s='none'; try { var d=app.activeDocument; s=d.name+' ('+d.layers.length+' layers)'; } catch(e) { s='none'; } s"
        )) ?? "unreachable"
        return "doc=\(probe)"
    }

    private func jsLayerCount() -> Int {
        (try? photoshopJS("var n=0; try{n=app.activeDocument.layers.length;}catch(e){n=0;} n")).flatMap(Int.init) ?? 0
    }

    private func openAsLayers() throws {
        guard let lr = lightroomApp() else {
            throw makeError(404, "Lightroom Classic isn’t running")
        }
        bringForward(lr)
        Thread.sleep(forTimeInterval: 0.85)
        try LightroomAccessibility.openAsLayers(pid: lr.processIdentifier)
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
        phase == .blending || (phase == .idle && isPhotoshopFrontmost())
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
