import Foundation
import Combine

struct FeatureWalkthroughManifest: Decodable {
    struct Step: Decodable {
        let id: String
        let title: String
        let body: String
        let target: String
        let gesture: String
        let zoom: String
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

/// Only explicit Done completes an installation. Replay never erases completion.
struct FeatureWalkthroughProgress {
    let defaults: UserDefaults
    let identity: String
    let count: Int
    private var prefix: String { "featureWalkthrough." + identity }
    var completed: Bool { defaults.bool(forKey: prefix + ".completed") }
    var index: Int { min(max(0, defaults.integer(forKey: prefix + ".index")), max(0, count - 1)) }
    func save(_ index: Int) {
        guard !completed else { return }
        defaults.set(min(max(0, index), max(0, count - 1)), forKey: prefix + ".index")
    }
    @discardableResult func finish(at index: Int) -> Bool {
        guard count > 0, index == count - 1 else { return false }
        defaults.set(true, forKey: prefix + ".completed")
        return true
    }
}

final class FeatureWalkthroughController: ObservableObject {
    static let shared = FeatureWalkthroughController()
    let manifest: FeatureWalkthroughManifest
    let progress: FeatureWalkthroughProgress
    @Published private(set) var index: Int?
    @Published private(set) var pending: Bool
    private var afterDone: (() -> Void)?

    init(defaults: UserDefaults = .standard, build: String? = nil,
         manifest: FeatureWalkthroughManifest = .current) {
        self.manifest = manifest
        let build = build ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development")
        progress = .init(defaults: defaults, identity: manifest.version + ":" + build + ":" + manifest.revision, count: manifest.steps.count)
        pending = !progress.completed
    }
    func presentAutomatically() {
        guard pending, index == nil else { return }
        index = progress.index
    }
    func replay(afterDone: (() -> Void)? = nil) {
        self.afterDone = afterDone
        index = 0
        progress.save(0)
    }
    func move(_ next: Int) {
        guard let current = index, abs(next - current) == 1, manifest.steps.indices.contains(next) else { return }
        index = next
        progress.save(next)
    }
    func later() {
        index = nil
        afterDone = nil
        pending = !progress.completed
    }
    func done() {
        guard let index, progress.finish(at: index) else { return }
        self.index = nil
        pending = false
        let completion = afterDone
        afterDone = nil
        completion?()
    }
}
