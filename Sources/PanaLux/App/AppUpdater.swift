import AppKit
import Sparkle

/// Sparkle owns download verification and installation; the private signing key stays in Keychain.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard !AppRuntime.isRenderingStills, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }
}
