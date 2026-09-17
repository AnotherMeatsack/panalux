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
        
        guard let menuBar = copyAttr(app, kAXMenuBarAttribute as String) else {
            throw axError("Couldn’t read Lightroom’s menu bar. Click the Lightroom window once, then try again.")
        }
        
        guard let photo = findChild(menuBar, titleContains: "Photo") else {
            throw axError("Couldn’t find Lightroom’s Photo menu.")
        }
        press(photo)
        usleep(280_000)
        
        guard let photoMenu = firstMenu(from: photo) ?? findChild(photo, role: kAXMenuRole as String) else {
            throw axError("Photo menu didn’t open.")
        }
        guard let editIn = findChild(photoMenu, titleContains: "Edit In") else {
            throw axError("Couldn’t find Photo → Edit In.")
        }
        press(editIn)
        usleep(320_000)
        
        guard let editMenu = firstMenu(from: editIn) ?? findChild(editIn, role: kAXMenuRole as String) else {
            throw axError("Edit In submenu didn’t open.")
        }
        guard let openLayers = findChild(editMenu, titleContains: "Open as Layers", excluding: "Smart Object") else {
            throw axError("Open as Layers wasn’t in Photo → Edit In. Select the photos in Library first.")
        }
        press(openLayers)
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
            if let button = findChild(window, titleContains: wanted, role: kAXButtonRole as String) {
                press(button)
                return true
            }
        }
        return false
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return true }
        return (value as? Bool) ?? true
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
