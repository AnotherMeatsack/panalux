import SwiftUI
import AppKit
import Combine

public class NotchHUDWindowController: ObservableObject {
    public static let shared = NotchHUDWindowController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<NotchHUDView>?
    private var glassView: NSView?
    private var cancellables = Set<AnyCancellable>()
    private var isHiding = false

    /// Readouts are 400 wide; Rewind is a timeline and gets room to be one. It is set from the
    /// mode before any frame is worked out, so the window, its content and its position agree.
    private var hudWidth: CGFloat = 400
    static let rewindWidth: CGFloat = 560

    static func width(for mode: ActiveDisplayMode) -> CGFloat {
        if case .rewind = mode, AppSettings.shared.hudStyle != "minimal" { return rewindWidth }
        return 400
    }
    /// The height the window is at or animating to. `window.frame` lags during animations.
    private var currentHeight: CGFloat = 0
    /// The display the readout is on. Chosen when it slides down and kept until it hides,
    /// so it never jumps between screens mid-toast.
    private weak var activeScreen: NSScreen?

    private init() {}

    public func setup() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: 68),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: NotchHUDView())
        hosting.frame = NSRect(x: 0, y: 0, width: hudWidth, height: 68)
        self.hostingView = hosting

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            glass.style = .regular
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = false
            }
            glass.contentView = hosting
            panel.contentView = glass
            self.glassView = glass
        } else {
            panel.contentView = hosting
        }

        self.window = panel
        applyContentSize(height: 68)
        if let rest = restFrame(height: 68) {
            panel.setFrame(rest, display: false)
        }

        HUDFeed.shared.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.handleDisplayModeChange(mode)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let s = self.activeScreen, !NSScreen.screens.contains(s) { self.activeScreen = nil }
                guard let window = self.window, window.isVisible, !self.isHiding else { return }
                self.updatePosition(height: window.frame.height)
            }
            .store(in: &cancellables)
    }

    private func handleDisplayModeChange(_ mode: ActiveDisplayMode) {
        guard AppSettings.shared.notchHudEnabled else {
            isHiding = false
            window?.alphaValue = 1
            window?.orderOut(nil)
            return
        }

        if mode == .idle {
            slideUpIntoNotch()
        } else {
            let height = Self.height(for: mode)
            let width = Self.width(for: mode)
            let widthChanged = abs(hudWidth - width) > 0.5
            hudWidth = width
            if let window, window.isVisible {
                // Values change every packet; only move the window when its size changes.
                if isHiding || widthChanged || abs(currentHeight - height) > 0.5 {
                    isHiding = false
                    slideToRest(height: height, fromHidden: false)
                }
            } else {
                slideDownFromNotch(height: height)
            }
        }
    }

    private func slideDownFromNotch(height: CGFloat) {
        activeScreen = Self.lightroomScreen()
        guard let window, let rest = restFrame(height: height), let tucked = tuckedFrame(height: height) else { return }
        isHiding = false
        applyContentSize(height: height)
        window.alphaValue = 0
        window.setFrame(tucked, display: true)
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.40
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(rest, display: true)
            window.animator().alphaValue = 1
        }
    }

    private func slideToRest(height: CGFloat, fromHidden: Bool) {
        guard let window else { return }
        if fromHidden || activeScreen == nil { activeScreen = Self.lightroomScreen() }
        guard let rest = restFrame(height: height) else { return }
        applyContentSize(height: height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fromHidden ? 0.40 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(rest, display: true)
            window.animator().alphaValue = 1
        }
    }

    private func slideUpIntoNotch() {
        guard let window, window.isVisible else { return }
        isHiding = true
        let tucked = tuckedFrame(height: window.frame.height) ?? {
            var f = window.frame
            if let screen = self.screen {
                f.origin.y = screen.frame.maxY - 2
            }
            return f
        }()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.36
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 0.15)
            window.animator().setFrame(tucked, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.isHiding else { return }
            self.isHiding = false
            if HUDFeed.shared.mode == .idle {
                self.activeScreen = nil
                self.window?.orderOut(nil)
                self.window?.alphaValue = 1
            }
        })
    }

    static func height(for mode: ActiveDisplayMode) -> CGFloat {
        if AppSettings.shared.hudStyle == "minimal" {
            return mode == .idle ? 34 : 38
        }
        switch mode {
        case .idle: return 48
        case .layerBanner(_, _, _, _, _, let grid):
            return grid.isEmpty ? 68 : 124
        case .multi(let readings):
            // One row fits in the same box as a single readout, so nothing jumps.
            return readings.count > 3 ? 104 : 68
        case .rewind(let state):
            // Header, the tape, a lane for each tangent, and the knobs. It grows with the tangents.
            return RewindView.height(tangentCount: state.tangents.count, hasKnobs: !state.knobs.isEmpty)
        default: return 68
        }
    }

    public func updatePosition(height: CGFloat) {
        guard let rest = restFrame(height: height) else { return }
        applyContentSize(height: height)
        window?.setFrame(rest, display: true)
    }

    private func applyContentSize(height: CGFloat) {
        currentHeight = height
        let bounds = NSRect(x: 0, y: 0, width: hudWidth, height: height)
        hostingView?.frame = bounds
        glassView?.frame = bounds
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = min(22, height / 2)
        }
    }

    private func restFrame(height: CGFloat) -> NSRect? {
        guard let screen else { return nil }
        let screenFrame = screen.frame
        let posX = screenFrame.midX - (hudWidth / 2.0)
        let gapBelowNotch: CGFloat = 10
        let posY: CGFloat
        let safeTop = screen.safeAreaInsets.top
        if safeTop > 24.0 {
            posY = screenFrame.maxY - safeTop - gapBelowNotch - height
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let bar = max(menuBarHeight, 28)
            posY = screenFrame.maxY - bar - gapBelowNotch - height
        }
        return NSRect(x: posX, y: posY, width: hudWidth, height: height)
    }

    private var screen: NSScreen? {
        activeScreen ?? Self.lightroomScreen()
    }

    private static let lightroomBundleIDs: Set<String> = ["com.adobe.LightroomClassicCC7", "com.adobe.Lightroom"]

    /// The screen showing Lightroom's biggest window. Not `NSScreen.main`, which follows
    /// whichever window has focus (for example PanaLux's own window on another display).
    /// Falls back to the menu-bar screen when Lightroom has no visible window.
    static func lightroomScreen() -> NSScreen? {
        let primary = NSScreen.screens.first
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { lightroomBundleIDs.contains($0.bundleIdentifier ?? "") }
            .map { $0.processIdentifier })
        guard !pids.isEmpty, let primaryHeight = primary?.frame.height,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return primary }

        var best: (area: CGFloat, rect: NSRect)?
        for w in info {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict) else { continue }
            let area = cg.width * cg.height
            guard area > 40_000, area > (best?.area ?? 0) else { continue }
            // Quartz is top-left of the primary display; AppKit is bottom-left.
            best = (area, NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height))
        }
        guard let rect = best?.rect else { return primary }
        return NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        } ?? primary
    }

    /// Parked just past the top of the display so the capsule reads as sliding into the notch.
    private func tuckedFrame(height: CGFloat) -> NSRect? {
        guard let rest = restFrame(height: height),
              let screen else { return nil }
        var tucked = rest
        tucked.origin.y = screen.frame.maxY - 2
        return tucked
    }
}
