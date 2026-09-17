import Foundation
import AppKit
import ApplicationServices

/// Click Lightroom menus through the Accessibility API (this app), not System Events.
/// System Events keystrokes/clicks are blocked on macOS 26/27 even when the app is trusted.
enum LightroomAccessibility {
    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return AXIsProcessTrusted()
    }
    
    /// Clicks Photo → Edit In → Open as Layers from the current module (usually Develop).
    /// Does not switch to Library Grid — that drops the filmstrip to one photo on the first send.
    static func openAsLayers(pid: pid_t) throws {
        guard isTrusted(prompt: true) else {
            throw NSError(
                domain: "PhotoshopBridge",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Allow PanaLux in System Settings → Privacy & Security → Accessibility, then press Grab Still once more."]
            )
        }

        let app = AXUIElementCreateApplication(pid)
        dismissSheets(app)
        cancelSinglePhotoEdit(pid: pid)

        var lastError: Error = axError("Open as Layers wasn’t in Photo → Edit In.")
        for attempt in 0..<8 {
            if let running = NSRunningApplication(processIdentifier: pid) {
                let apply = {
                    _ = running.unhide()
                    NSApp.yieldActivation(to: running)
                    _ = running.activate(from: NSRunningApplication.current)
                }
                if Thread.isMainThread { apply() } else { DispatchQueue.main.sync(execute: apply) }
            }
            usleep(UInt32(200_000 + attempt * 80_000))
            do {
                try clickOpenAsLayers(app: app, pid: pid)
                usleep(280_000)
                _ = confirmLayersDialog(pid: pid)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func clickOpenAsLayers(app: AXUIElement, pid: pid_t) throws {
        guard let menuBar = copyAttr(app, kAXMenuBarAttribute as String) else {
            throw axError("Couldn’t read Lightroom’s menu bar. Click the Lightroom window once, then try again.")
        }
        guard let tops = copyList(menuBar, kAXChildrenAttribute as String),
              let photo = tops.first(where: {
                  let t = title(of: $0).trimmingCharacters(in: .whitespaces)
                  return t.caseInsensitiveCompare("Photo") == .orderedSame
              }) else {
            throw axError("Couldn’t find Lightroom’s Photo menu.")
        }
        press(photo)
        usleep(450_000)

        guard let photoMenu = firstMenu(from: photo) else {
            cancel(photo)
            throw axError("Photo menu didn’t open.")
        }
        guard let editIn = menuItem(photoMenu, containing: "Edit In") else {
            cancel(photo)
            throw axError("Couldn’t find Photo → Edit In.")
        }
        showSubmenu(editIn)
        usleep(550_000)

        // Lightroom sometimes fires “Edit in Photoshop” (one photo) when Edit In opens.
        cancelSinglePhotoEdit(pid: pid)

        guard let editMenu = firstMenu(from: editIn) else {
            cancel(photo)
            throw axError("Edit In submenu didn’t open.")
        }
        guard let openLayers = menuItem(editMenu, containing: "Open as Layers", excluding: "Smart Object") else {
            cancel(photo)
            throw axError("Open as Layers wasn’t in Photo → Edit In. Select the photos in the filmstrip.")
        }
        press(openLayers)
    }

    /// Confirm only the multi-photo / layers dialog. Never confirm “Edit Photo” (singular).
    @discardableResult
    static func confirmLayersDialog(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline {
            if confirmMatchingSheet(app, mustContainAny: ["as layers", "edit photos"]) { return true }
            usleep(180_000)
        }
        return false
    }

    /// The leftover Develop alert after coming back from Photoshop.
    static func dismissNoSelectionDialog(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        for _ in 0..<6 {
            if confirmMatchingSheet(app, mustContainAny: ["no photo selected", "no photos selected"], buttons: ["OK", "Continue"]) {
                usleep(100_000)
                continue
            }
            break
        }
    }

    @discardableResult
    private static func confirmMatchingSheet(
        _ app: AXUIElement,
        mustContainAny needles: [String],
        buttons: [String] = ["Edit", "Continue"]
    ) -> Bool {
        for sheet in sheets(app) {
            let blob = sheetText(sheet)
            let hit = needles.contains { blob.contains($0) }
            guard hit else { continue }
            for wanted in buttons {
                if let button = findChild(sheet, titleContains: wanted, role: kAXButtonRole as String),
                   isEnabled(button) {
                    let t = title(of: button).lowercased()
                    if t.contains("cancel") { continue }
                    press(button)
                    return true
                }
            }
        }
        return false
    }

    private static func cancelSinglePhotoEdit(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        for sheet in sheets(app) {
            let blob = sheetText(sheet)
            let isLayers = blob.contains("as layers") || blob.contains("edit photos")
            let isSingle = (blob.contains("edit photo") && !blob.contains("edit photos")) || blob.contains("too many")
            guard isSingle, !isLayers else { continue }
            if let cancel = findChild(sheet, titleContains: "Cancel", role: kAXButtonRole as String) {
                press(cancel)
                usleep(120_000)
            }
        }
    }

    private static func sheets(_ app: AXUIElement) -> [AXUIElement] {
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return [] }
        return windows.filter {
            let r = role(of: $0)
            return r.contains("Sheet") || r.contains("Dialog")
        }
    }

    private static func sheetText(_ sheet: AXUIElement) -> String {
        var parts = [title(of: sheet)]
        if let kids = copyList(sheet, kAXChildrenAttribute as String) {
            for child in kids.prefix(20) {
                parts.append(title(of: child))
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private static func menuItem(_ menu: AXUIElement, containing needle: String, excluding: String? = nil) -> AXUIElement? {
        guard let kids = copyList(menu, kAXChildrenAttribute as String) else { return nil }
        return kids.first { child in
            let t = title(of: child)
            guard t.localizedCaseInsensitiveContains(needle) else { return false }
            if let excluding, t.localizedCaseInsensitiveContains(excluding) { return false }
            return true
        }
    }

    /// True while Lightroom is still writing copies or handing files to Photoshop.
    static func isWorkingSheetVisible(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return false }
        for window in windows {
            let r = role(of: window)
            if r.contains("Sheet") || r.contains("Dialog") { return true }
            let t = title(of: window).lowercased()
            if t.contains("photoshop") || t.contains("edit photo") || t.contains("progress") {
                return true
            }
            if hasProgressIndicator(window) { return true }
        }
        return false
    }

    /// Standard windows with a title, ignoring app home screens (title is just the app name).
    static func namedWindowCount(pid: pid_t, skippingTitles: [String]) -> Int {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return 0 }
        return windows.filter { window in
            let t = title(of: window).trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return false }
            let lower = t.lowercased()
            for skip in skippingTitles {
                if lower == skip { return false }
                if lower.hasPrefix(skip), !lower.contains("."), !lower.contains("untitled") {
                    return false
                }
            }
            return true
        }.count
    }
    
    /// Press a menu item by title, opening the named top-level menus one at a time.
    /// Returns false when the item isn't there (wrong module, nothing selected).
    @discardableResult
    static func pressMenuItem(pid: pid_t, titles: [String], menus: [String], excluding: String? = nil) -> Bool {
        guard isTrusted(prompt: true) else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = copyAttr(app, kAXMenuBarAttribute as String),
              let tops = copyList(menuBar, kAXChildrenAttribute as String) else { return false }
        for menuTitle in menus {
            guard let top = tops.first(where: { title(of: $0) == menuTitle }) else { continue }
            // Lightroom fills some menus only when they open.
            var menu = firstMenu(from: top)
            var opened = false
            if menu.map({ (copyList($0, kAXChildrenAttribute as String) ?? []).isEmpty }) ?? true {
                press(top)
                opened = true
                usleep(220_000)
                menu = firstMenu(from: top)
            }
            if let menu {
                for wanted in titles {
                    if let item = findChild(menu, titleContains: wanted, excluding: excluding), isEnabled(item) {
                        press(item)
                        return true
                    }
                }
            }
            if opened { AXUIElementPerformAction(top, kAXCancelAction as CFString) }
        }
        return false
    }

    /// Press a button in an open Lightroom dialog (e.g. "Synchronize"). False if none is open.
    static func pressDialogButton(pid: pid_t, title wanted: String) -> Bool {
        guard isTrusted(prompt: false) else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return false }
        for window in windows {
            if let button = findChild(window, titleContains: wanted, role: kAXButtonRole as String), isEnabled(button) {
                press(button)
                return true
            }
        }
        return false
    }

    @discardableResult
    private static func clickSheetButton(_ app: AXUIElement, titles: [String]) -> Bool {
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return false }
        let sheets = windows.filter {
            let r = role(of: $0)
            return r.contains("Sheet") || r.contains("Dialog")
        }
        for window in sheets {
            for wanted in titles {
                if let button = findChild(window, titleContains: wanted, role: kAXButtonRole as String), isEnabled(button) {
                    let t = title(of: button).lowercased()
                    if t.contains("cancel") { continue }
                    press(button)
                    return true
                }
            }
        }
        return false
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return true }
        return (value as? Bool) ?? true
    }

    private static func showSubmenu(_ element: AXUIElement) {
        let shown = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        if shown != .success {
            press(element)
        }
    }

    private static func cancel(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXCancelAction as CFString)
    }

    private static func hasProgressIndicator(_ element: AXUIElement) -> Bool {
        if role(of: element).contains("Progress") { return true }
        guard let kids = copyList(element, kAXChildrenAttribute as String) else { return false }
        return kids.prefix(12).contains { hasProgressIndicator($0) }
    }

    private static func dismissSheets(_ app: AXUIElement) {
        guard let windows = copyList(app, kAXWindowsAttribute as String) else { return }
        for window in windows.prefix(3) {
            guard let kids = copyList(window, kAXChildrenAttribute as String) else { continue }
            for child in kids {
                let r = role(of: child)
                if r.contains("Sheet") || r.contains("Dialog") {
                    if let ok = findChild(child, titleContains: "OK") ?? findChild(child, titleContains: "Continue") {
                        press(ok)
                        usleep(150_000)
                    }
                }
            }
        }
    }
    
    private static func firstMenu(from element: AXUIElement) -> AXUIElement? {
        if let kids = copyList(element, kAXChildrenAttribute as String) {
            return kids.first { role(of: $0) == (kAXMenuRole as String) }
        }
        return nil
    }
    
    private static func findChild(
        _ parent: AXUIElement,
        titleContains needle: String? = nil,
        excluding: String? = nil,
        role wantedRole: String? = nil
    ) -> AXUIElement? {
        guard let kids = copyList(parent, kAXChildrenAttribute as String) else { return nil }
        for child in kids {
            if let wantedRole, role(of: child) != wantedRole { continue }
            let t = title(of: child)
            if let needle, !t.localizedCaseInsensitiveContains(needle) { continue }
            if let excluding, t.localizedCaseInsensitiveContains(excluding) { continue }
            if needle != nil || wantedRole != nil { return child }
        }
        for child in kids {
            if let nested = findChild(child, titleContains: needle, excluding: excluding, role: wantedRole) {
                return nested
            }
        }
        return nil
    }
    
    private static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
    
    private static func title(of element: AXUIElement) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return ""
        }
        return (value as? String) ?? ""
    }
    
    private static func role(of element: AXUIElement) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return ""
        }
        return (value as? String) ?? ""
    }
    
    private static func copyAttr(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard err == .success, let value else { return nil }
        return (value as! AXUIElement)
    }
    
    private static func copyList(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard err == .success else { return nil }
        return value as? [AXUIElement]
    }
    
    private static func axError(_ message: String) -> NSError {
        NSError(domain: "PhotoshopBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
