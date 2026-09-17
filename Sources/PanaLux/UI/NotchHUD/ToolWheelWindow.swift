import SwiftUI
import AppKit
import Combine

/// Full circular overlay on Lightroom’s screen — the mask tool wheel.
public final class ToolWheelWindowController: ObservableObject {
    public static let shared = ToolWheelWindowController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<ToolWheelView>?
    private var cancellables = Set<AnyCancellable>()
    private let size: CGFloat = 400

    private init() {}

    public func setup() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: ToolWheelView())
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hostingView = hosting
        panel.contentView = hosting

        window = panel

        ToolWheelSession.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shown in
                if shown { self?.show() } else { self?.hide() }
            }
            .store(in: &cancellables)
    }

    private func show() {
        guard let window else { return }
        let screen = NotchHUDWindowController.lightroomScreen() ?? NSScreen.main
        let frame = screen.map {
            NSRect(x: $0.frame.midX - size / 2, y: $0.frame.midY - size / 2, width: size, height: size)
        } ?? window.frame
        window.setFrame(frame, display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 0.15)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.window?.alphaValue == 0 else { return }
            self?.window?.orderOut(nil)
            self?.window?.alphaValue = 1
        })
    }
}
