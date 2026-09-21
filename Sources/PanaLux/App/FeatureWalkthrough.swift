import Foundation
import Combine

/// "1.2.6" as a comparable value. Missing parts count as zero.
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let parts: [Int]
    init?(_ text: String) {
        let numbers = text.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        parts = numbers.compactMap { $0 }
    }
    var description: String { parts.map(String.init).joined(separator: ".") }
    static func < (a: Self, b: Self) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    static func == (a: Self, b: Self) -> Bool { !(a < b) && !(b < a) }
}

/// What changed, authored per release. `since` is the version where a feature arrived or was
/// last changed, so people only see what is new to them.
struct FeatureWalkthroughManifest: Decodable {
    struct Step: Decodable, Identifiable {
        let id: String
        let title: String
        let body: String
        /// Version this item arrived in, or last changed in.
        let since: String
        /// "new" or "updated".
        let kind: String
        /// Which real control the spotlight lands on.
        let target: String
        /// Optional "Try it" button in the spotlight card.
        let action: String?
        var version: AppVersion { AppVersion(since) ?? AppVersion("0")! }
    }
    let version: String
    let revision: String
    let changelogHeadings: [String]
    let steps: [Step]
    static let current: Self = {
        guard let data = AppResources.data("FeatureWalkthrough", "json"),
              let value = try? JSONDecoder().decode(Self.self, from: data), !value.steps.isEmpty else {
            preconditionFailure("A release must bundle its authored feature walkthrough")
        }
        return value
    }()
}

/// Remembers the newest version whose changes this person has been shown.
struct WhatsNewStore {
    let defaults: UserDefaults
    private let seenKey = "whatsNew.lastSeenVersion"
    private let fromKey = "whatsNew.lastShownFrom"

    /// The version they already know. `nil` means a brand new install, which gets the intro instead.
    func lastSeen(onboarded: Bool) -> AppVersion? {
        if let text = defaults.string(forKey: seenKey), let v = AppVersion(text) { return v }
        // Before this existed, 1.2.4+ recorded each finished walkthrough as "featureWalkthrough.<version>:<build>:<rev>.completed".
        let legacy = defaults.dictionaryRepresentation().keys.compactMap { key -> AppVersion? in
            guard key.hasPrefix("featureWalkthrough."), key.hasSuffix(".completed") else { return nil }
            let body = key.dropFirst("featureWalkthrough.".count)
            return AppVersion(String(body.prefix { $0 != ":" }))
        }
        if let newest = legacy.max() { return newest }
        return onboarded ? AppVersion("1.2.0") : nil
    }

    func markSeen(_ version: AppVersion, from: AppVersion?) {
        defaults.set(version.description, forKey: seenKey)
        if let from { defaults.set(from.description, forKey: fromKey) }
    }

    var lastShownFrom: AppVersion? { defaults.string(forKey: fromKey).flatMap(AppVersion.init) }
}

/// Changelog first; closing it walks the spotlight through each item on the real window.
final class WhatsNewController: ObservableObject {
    static let shared = WhatsNewController()
    let manifest: FeatureWalkthroughManifest
    private let store: WhatsNewStore
    private let current: AppVersion

    @Published private(set) var showingChangelog = false
    @Published private(set) var spotlightIndex: Int?
    @Published private(set) var items: [FeatureWalkthroughManifest.Step] = []
    /// The version the items are measured against, for "Since 1.2.4".
    @Published private(set) var since: AppVersion?

    init(defaults: UserDefaults = .standard, currentVersion: String? = nil,
         manifest: FeatureWalkthroughManifest = .current) {
        self.manifest = manifest
        store = WhatsNewStore(defaults: defaults)
        let bundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        current = AppVersion(currentVersion ?? bundle ?? manifest.version) ?? AppVersion(manifest.version)!
    }

    /// Only what changed after `version`, up to this release.
    func items(after version: AppVersion?) -> [FeatureWalkthroughManifest.Step] {
        manifest.steps.filter { step in step.version <= current && (version.map { step.version > $0 } ?? true) }
    }

    /// Launch: show the changelog once per update, for the changes this person hasn't seen.
    func presentAfterUpdate(onboarded: Bool) {
        guard !showingChangelog, spotlightIndex == nil else { return }
        let known = store.lastSeen(onboarded: onboarded)
        defer { store.markSeen(current, from: known) }
        guard let known, known < current else { return }
        let fresh = items(after: known)
        guard !fresh.isEmpty else { return }
        items = fresh
        since = known
        showingChangelog = true
    }

    /// Menu: show it again, for the same span of updates as last time.
    func replay() {
        let from = store.lastShownFrom
        var list = items(after: from)
        if list.isEmpty { list = manifest.steps.filter { $0.version == current } }
        if list.isEmpty { list = Array(manifest.steps.prefix(3)) }
        items = list
        since = from
        showingChangelog = true
        spotlightIndex = nil
    }

    /// Closing the changelog starts the spotlight unless the person skips it.
    func closeChangelog(showMeWhere: Bool = true) {
        guard showingChangelog else { return }
        showingChangelog = false
        spotlightIndex = showMeWhere && !items.isEmpty ? 0 : nil
    }

    func move(_ delta: Int) {
        guard let i = spotlightIndex else { return }
        let next = i + delta
        if items.indices.contains(next) { spotlightIndex = next } else if next >= items.count { finish() }
    }

    func finish() { spotlightIndex = nil }
}
