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
    /// True while auto-align is running. Saving then would flatten a half-aligned stack.
    private var aligningValue = false
    private var aligning: Bool {
        get { busyLock.lock(); defer { busyLock.unlock() }; return aligningValue }
        set { busyLock.lock(); aligningValue = newValue; busyLock.unlock() }
    }
    /// The document this send produced. Photoshop opens an incoming stack behind
    /// whatever is already on screen, so `app.activeDocument` is usually something
    /// else entirely and must never be what gets counted, flattened or closed.
    private var targetDocumentID: Int? = nil
    private var documentsBeforeSend: Set<Int> = []
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
            if aligning { return "Still aligning the layers… press again in a moment" }
            if targetDocumentID.map({ layerCount(ofDocument: $0) > 0 }) ?? (jsDocumentCount() > 0) {
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
        // Photoshop first, menus second.
        //
        // Read the count before touching menus: activating Lightroom and walking its
        // menu bar is exactly when a selection can change underneath us.
        expectedLayers = LightroomBridge.shared.selectedPhotoCount ?? 0
        let module = LightroomBridge.shared.currentModule ?? "unreported"
        // Ask, don't just check. Checking without prompting meant a key press could
        // report the permission missing while never giving macOS the chance to offer it,
        // so the dialog never appeared no matter how many times it was pressed.
        let trusted = LightroomAccessibility.isTrusted(prompt: true)
        log("SEND  selected=\(expectedLayers)  module=\(module)  bracket=\(fromBracket)  accessibility=\(trusted)  photoshopUp=\(isPhotoshopRunning())")
        guard trusted else {
            throw makeError(403, "Allow PanaLux in System Settings → Privacy & Security → Accessibility, then press Grab Still again.")
        }
        // Have Photoshop up and answering before Lightroom is asked to hand it a stack.
        ensurePhotoshopReady()
        // After a save PanaLux hides Photoshop to bring Lightroom back. A hidden Photoshop is the
        // one that got a single photo of the stack, so show it again, without raising it.
        let wasHidden = showPhotoshopIfHidden()
        log("photoshop hidden=\(wasHidden)")
        documentsBeforeSend = openDocumentIDs()
        targetDocumentID = nil
        log("before: \(documentsBeforeSend.count) document(s) already open")
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

    /// Watch the stack land, then check it is all there.
    ///
    /// This used to wait for Lightroom to look idle first, by scanning every window for
    /// a progress indicator. Lightroom keeps sixteen windows open and there is nearly
    /// always a progress indicator somewhere in one of them, so that check never once
    /// returned true: the watcher sat for its full timeout, the layer count was never
    /// compared against the selection, and a short stack was never caught. What actually
    /// matters is whether the stack has stopped growing in Photoshop, so that is what is
    /// watched now.
    private func watchForStack(cameFromBracket: Bool) {
        watchQueue.async {
            // Let Lightroom get the export under way before anything else happens, and
            // clear the "Edit Photos" dialog if it is waiting for an answer.
            for _ in 0..<10 {
                if let lr = self.lightroomApp() {
                    _ = LightroomAccessibility.confirmLayersDialog(pid: lr.processIdentifier)
                }
                if self.isPhotoshopRunning() { break }
                Thread.sleep(forTimeInterval: 0.6)
            }
            guard self.waitForPhotoshop(timeout: 180) else {
                self.phase = .blending
                self.log("RESULT Photoshop never opened")
                self.report("Photoshop didn’t open. Press Grab Still again when it has.")
                return
            }

            guard let (docID, layers) = self.waitForNewStack(timeout: 240) else {
                self.phase = .blending
                self.log("RESULT no new document appeared in Photoshop")
                self.report("Couldn’t see the stack in Photoshop. Align it yourself, then press Grab Still to save.")
                return
            }
            self.targetDocumentID = docID
            // Photoshop left it behind the documents that were already open.
            self.bringDocumentToFront(docID)
            self.log("RESULT \(layers) layer(s), expected \(self.expectedLayers)  doc id=\(docID)")

            // A short stack. This is caught before anything has been blended — the stack
            // has only just landed and PanaLux has not said it is ready — so closing it
            // and sending again cannot throw work away.
            if self.expectedLayers > 1, layers < self.expectedLayers, !self.resentForShortStack {
                self.resentForShortStack = true
                self.report("Only \(layers) of \(self.expectedLayers) arrived. Sending again…")
                self.closeActivePhotoshopDocument()
                Thread.sleep(forTimeInterval: 1.5)
                // The first attempt left Photoshop in front, which is exactly when Lightroom's
                // Photo menu cannot be reached. Bring Lightroom back and try again rather than
                // giving up on the first refusal.
                var lastError = ""
                for attempt in 1...3 {
                    self.activateLightroom()
                    Thread.sleep(forTimeInterval: 1.2)
                    do {
                        _ = try self.sendStack(fromBracket: cameFromBracket)
                        return
                    } catch {
                        lastError = error.localizedDescription
                        self.log("resend attempt \(attempt) failed: \(lastError)")
                    }
                }
                self.phase = .blending
                self.log("resend failed: \(lastError)")
                self.report("Only \(layers) of \(self.expectedLayers) arrived and the resend failed. Press Grab Still again.")
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
            self.aligning = true
            defer { self.aligning = false }
            do {
                self.report(try self.alignLayers())
            } catch {
                self.log("align failed: \(error.localizedDescription)")
                self.report("Opened \(layers) layers. Auto-align didn’t run.")
            }
        }
    }

    /// Launch Photoshop, without stealing the screen, and wait until it answers.
    /// A cold Photoshop is the condition under which Lightroom hands over one photo
    /// instead of the whole stack.
    private func ensurePhotoshopReady(timeout: TimeInterval = 120) {
        if !isPhotoshopRunning() {
            log("prewarm: Photoshop is not running, launching it")
            let bundle = photoshopBundleId()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                let done = DispatchSemaphore(value: 0)
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
                _ = done.wait(timeout: .now() + 30)
            }
        }
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if isPhotoshopRunning(), (try? photoshopJS("app.documents.length")) != nil {
                log("prewarm: Photoshop is ready")
                return
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        log("prewarm: Photoshop never answered; sending anyway")
    }

    // MARK: - Documents by identity

    /// Every open document's id. A stack that has just arrived is the id that is new.
    private func openDocumentIDs() -> Set<Int> {
        let raw = (try? photoshopJS(
            "var a=[]; for(var i=0;i<app.documents.length;i++){a.push(app.documents[i].id);} a.join(',')"
        )) ?? ""
        return Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private static func docByIDPrelude() -> String {
        "function __d(id){for(var i=0;i<app.documents.length;i++){if(app.documents[i].id==id){return app.documents[i];}}return null;}"
    }

    private func layerCount(ofDocument id: Int) -> Int {
        let js = Self.docByIDPrelude() + "var d=__d(\(id)); d ? d.layers.length : -1"
        return (try? photoshopJS(js)).flatMap(Int.init) ?? -1
    }

    private func bringDocumentToFront(_ id: Int) {
        let js = Self.docByIDPrelude() + "var d=__d(\(id)); if(d){app.activeDocument=d;} 'ok'"
        _ = try? photoshopJS(js)
    }

    /// The document that arrived from this send, or nil while none has.
    private func newDocumentID() -> Int? {
        openDocumentIDs().subtracting(documentsBeforeSend).sorted().last
    }

    private func isPhotoshopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains(where: isPhotoshop)
    }

    /// Photoshop has to be up before its document can be counted. Talking to it while it
    /// is still launching is what used to steal Lightroom's menu bar mid-export.
    private func waitForPhotoshop(timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if isPhotoshopRunning() { return true }
            if let lr = lightroomApp() {
                _ = LightroomAccessibility.confirmLayersDialog(pid: lr.processIdentifier)
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        return false
    }

    /// Wait for a document that was not open before this send, then for its layer
    /// count to stop changing. Following the *new* document matters: Photoshop opens an
    /// incoming stack behind whatever is already on screen, so the active document is
    /// usually one of the old ones and counting it reported a stale, already-stable
    /// number as though it were the result.
    private func waitForNewStack(timeout: TimeInterval) -> (Int, Int)? {
        let end = Date().addingTimeInterval(timeout)
        var docID: Int? = nil
        let began = Date()
        var lastNote = began
        while Date() < end, docID == nil {
            docID = newDocumentID()
            if docID == nil {
                Thread.sleep(forTimeInterval: 1.0)
                if Date().timeIntervalSince(lastNote) >= 20 {
                    lastNote = Date()
                    let waited = Int(Date().timeIntervalSince(began))
                    let hidden = NSWorkspace.shared.runningApplications.first(where: isPhotoshop)?.isHidden ?? false
                    log("still waiting for the stack: \(waited)s  photoshopHidden=\(hidden)  frontmost=\(isPhotoshopFrontmost() ? "photoshop" : "other")")
                    if waited >= 40 { report("Still waiting for Lightroom to hand over the stack… (\(waited)s)") }
                }
            }
        }
        guard let id = docID else { return nil }

        var previous = -1
        var stableRuns = 0
        while Date() < end {
            let count = layerCount(ofDocument: id)
            if count > 0 && count == previous {
                stableRuns += 1
                if stableRuns >= 3 { return (id, count) }
            } else {
                stableRuns = 0
            }
            previous = count
            Thread.sleep(forTimeInterval: 1.2)
        }
        return previous > 0 ? (id, previous) : nil
    }

    /// Select every layer and auto-align. This is what lines the brackets up.
    @discardableResult
    private func alignLayers() throws -> String {
        let target = targetDocumentID.map { "__d(\($0))" } ?? "app.activeDocument"
        let js = Self.docByIDPrelude() + """
        app.displayDialogs = DialogModes.NO;
        var out;
        try {
          if (app.documents.length < 1) { out = "ERR:no document"; }
          else {
            var d = \(target);
            if (!d) { throw "the document this send produced is no longer open"; }
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
            Self.docByIDPrelude() + "app.displayDialogs = DialogModes.NO; "
            + (targetDocumentID.map { "var d=__d(\($0)); if(d){ d.close(SaveOptions.DONOTSAVECHANGES); } 'ok';" }
               ?? "try { app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); } catch (e) {} 'ok';")
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
            // Quitting here is what made the next hand-off fail. Lightroom gives a
            // whole stack to a Photoshop that is already up; to one it has to launch it
            // often gives only the first photo. Closing the last document and quitting
            // guaranteed the next send started cold.
            if i == steps.count - 1, isPhotoshopFrontmost(), AppSettings.shared.quitPhotoshopWhenEmpty {
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
        let saveTarget = targetDocumentID.map { "__d(\($0))" } ?? "app.activeDocument"
        let probe = (try? photoshopJS(
            Self.docByIDPrelude()
            + "app.displayDialogs=DialogModes.NO; if(app.documents.length<1){'0|';} else { var d=\(saveTarget); if(!d){'0|';} else { var p=''; try{p=d.fullName.fsName;}catch(e){p='';} d.layers.length + '|' + p; } }"
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
        let js = Self.docByIDPrelude() + """
        app.displayDialogs = DialogModes.NO;
        try {
          if (app.documents.length < 1) { throw "no document"; }
          var d = \(saveTarget);
          if (!d) { throw "the blend this send produced is no longer open"; }
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
          out;
        } catch (e) { "ERR:" + e; }
        """
        let out = try photoshopJS(js).trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("ERR:") {
            log("SAVE FAILED  \(out)")
            throw makeError(500, "Photoshop couldn’t save: \(out.dropFirst(4))")
        }
        // Trust the disk, not the reply. The blend is only closed once a file with something in
        // it is really there; until then it is still open and nothing has been lost.
        let size = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? NSNumber)?.intValue ?? 0
        guard !out.isEmpty, size > 0 else {
            log("SAVE UNCONFIRMED  reply=\"\(out)\"  layers=\(layerCount)  doc=\(docPath.isEmpty ? "unsaved" : docPath)")
            throw makeError(500, "Photoshop didn’t confirm the save. The blend is still open. Press Grab Still again.")
        }
        closeActivePhotoshopDocument()
        targetDocumentID = nil
        log("SAVED \(out)  (\(size / 1024) KB)")
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
    
    /// Photoshop itself, never one of its helpers.
    ///
    /// Photoshop runs four WebKit and Safari helper processes, and every one of them is
    /// named after it — "Adobe Photoshop (Beta) Web Content", "AutoFill (Adobe Photoshop
    /// (Beta))" and so on. Matching on the name alone could pick one of those out of the
    /// running-applications list, and then every AppleScript call went to a WebKit
    /// process instead of Photoshop and quietly failed. Which one came back first was
    /// not deterministic, which is part of why this behaved differently run to run.
    private func isPhotoshop(_ app: NSRunningApplication) -> Bool {
        let bid = (app.bundleIdentifier ?? "").lowercased()
        if bid.hasPrefix("com.apple.") { return false }
        if bid.hasPrefix("com.adobe.photoshop") { return true }
        // Anything else has to be a real app with a dock presence, not a helper.
        guard app.activationPolicy == .regular else { return false }
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

    /// Make Photoshop visible again if it was hidden, and leave whatever is in front in front.
    @discardableResult
    private func showPhotoshopIfHidden() -> Bool {
        guard let ps = NSWorkspace.shared.runningApplications.first(where: isPhotoshop), ps.isHidden else {
            return false
        }
        let apply = { _ = ps.unhide() }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.sync(execute: apply) }
        if let bid = ps.bundleIdentifier {
            _ = try? runAppleScript("""
            tell application "System Events"
              try
                set visible of (first process whose bundle identifier is "\(bid)") to true
              end try
            end tell
            """)
        }
        return true
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
        let running = NSWorkspace.shared.runningApplications
            .filter { isPhotoshop($0) }
            .compactMap { $0.bundleIdentifier }
        // Prefer the real application bundle over anything else that slipped through.
        if let exact = running.first(where: { $0.lowercased().hasPrefix("com.adobe.photoshop") }) {
            return exact
        }
        return running.first ?? "com.adobe.Photoshop"
    }
    
    /// Every call to Photoshop goes through here, one at a time, each with a script file of its own.
    /// It used to write every script to one shared file from whichever thread was calling, and the
    /// watcher polls Photoshop every second or so while a stack arrives. A save pressed in that
    /// window could have its script overwritten by a poll's before Photoshop read it, and run the
    /// wrong thing: a save that logged "SAVED" with no path and wrote no file.
    private let photoshopCallLock = NSLock()

    private func photoshopJS(_ js: String) throws -> String {
        photoshopCallLock.lock()
        defer { photoshopCallLock.unlock() }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("panalux-ps-\(UUID().uuidString).js")
        defer { try? FileManager.default.removeItem(at: url) }
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
