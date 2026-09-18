import Foundation
import CoreGraphics

/// Lightroom features the plugin can't reach, run through Lightroom's own menus.
/// Stored on a key as `lr_menu:<id>`.
public enum LightroomMenuActions {
    public static let prefix = "lr_menu:"

    public struct Item {
        public let id: String
        public let title: String
        public let subtitle: String
        public let icon: String
        let titles: [String]
        let menus: [String]
        var excluding: String? = nil
        /// Fallback shortcut: key + modifier bits (1 Option, 2 Control, 4 Shift, 8 Command).
        let key: (String, Int)?
    }

    public static let items: [Item] = [
        Item(id: "sync", title: "Sync Settings",
             subtitle: "Opens Sync Settings for the selected photos. Press again to Synchronize.",
             icon: "arrow.triangle.2.circlepath",
             titles: ["Sync Settings"], menus: ["Settings", "Photo", "Develop"], key: ("s", 12)),
        Item(id: "select_all", title: "Select All Photos",
             subtitle: "Selects every photo in the filmstrip",
             icon: "checkmark.rectangle.stack",
             titles: ["Select All"], menus: ["Edit"], key: ("a", 8)),
        Item(id: "select_none", title: "Select None",
             subtitle: "Keeps only the photo you are editing",
             icon: "rectangle.stack",
             titles: ["Select None", "Select Only Active Photo"], menus: ["Edit"], key: ("d", 8)),
        Item(id: "auto_sync", title: "Auto Sync On/Off",
             subtitle: "While on, every change applies to all selected photos",
             icon: "arrow.triangle.2.circlepath.circle",
             titles: ["Auto Sync"], menus: ["Settings", "Develop"], key: ("a", 13)),
        Item(id: "bracket_show", title: "Show Bracket",
             subtitle: "Switches the filmstrip to the Quick Collection you gathered",
             icon: "rectangle.stack.badge.person.crop",
             titles: ["Show Quick Collection", "Quick Collection"], menus: ["File", "Library"], key: ("b", 8)),
        Item(id: "bracket_clear", title: "Clear Bracket",
             subtitle: "Empties the Quick Collection and starts a new bracket",
             icon: "xmark.rectangle.portrait",
             titles: ["Clear Quick Collection"], menus: ["File", "Library"], key: ("b", 12)),
        Item(id: "match_exposure", title: "Match Total Exposures",
             subtitle: "Evens out exposure across the selected photos",
             icon: "sun.max.trianglebadge.exclamationmark",
             titles: ["Match Total Exposures"], menus: ["Settings", "Photo", "Develop"], key: ("m", 13)),
    ]

    public static func item(_ action: String) -> Item? {
        guard action.hasPrefix(prefix) else { return nil }
        let id = String(action.dropFirst(prefix.count))
        return items.first { $0.id == id }
    }

    public static func title(_ action: String) -> String? { item(action)?.title }

    public enum Outcome { case done(String), failed(String) }

    /// Runs off the main thread (menu presses wait for Lightroom).
    public static func run(_ action: String, completion: @escaping (Outcome) -> Void) {
        guard let item = item(action) else { return completion(.failed("Unknown Lightroom command")) }
        guard let pid = LightroomKeys.lightroomPID else { return completion(.failed("Lightroom isn’t open")) }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Outcome
            if item.id == "sync", LightroomAccessibility.pressDialogButton(pid: pid, title: "Synchronize") {
                result = .done("Synchronized")
            } else if LightroomAccessibility.pressMenuItem(pid: pid, titles: item.titles, menus: item.menus, excluding: item.excluding) {
                result = .done(item.id == "sync" ? "Sync Settings · press again to Synchronize" : item.title)
            } else if let (key, bits) = item.key {
                var flags: CGEventFlags = []
                if bits & 1 != 0 { flags.insert(.maskAlternate) }
                if bits & 2 != 0 { flags.insert(.maskControl) }
                if bits & 4 != 0 { flags.insert(.maskShift) }
                if bits & 8 != 0 { flags.insert(.maskCommand) }
                result = LightroomKeys.press(key, flags: flags)
                    ? .done(item.title)
                    : .failed("Allow PanaLux in Privacy & Security → Accessibility")
            } else {
                result = .failed("\(item.title) isn’t available here")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
