import AppKit
import ApplicationServices

/// Moves and clicks the system pointer from a trackball, so mask tools can be
/// placed without taking a hand off the panel. Needs Accessibility permission.
enum PointerDriver {
    private static var mouseIsDown = false
    private static var sizeUpWork: DispatchWorkItem?

    static func move(dx: Double, dy: Double) {
        let loc = NSEvent.mouseLocation
        let next = CGPoint(x: loc.x + dx, y: loc.y + dy)
        postMouse(at: cocoaToQuartz(next), dragging: mouseIsDown)
    }

    /// Drag to resize a radial or linear mask. Mouse goes up shortly after the ring stops.
    static func resize(delta: Double) {
        sizeUpWork?.cancel()
        if !mouseIsDown { setDown(true) }
        move(dx: delta, dy: delta * 0.15)
        let work = DispatchWorkItem { setDown(false) }
        sizeUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    static func perform(_ command: String) {
        switch command {
        case PointerCommands.click:
            click()
        case PointerCommands.down:
            setDown(true)
        case PointerCommands.up:
            setDown(false)
        default:
            break
        }
    }

    static func click() {
        let p = cocoaToQuartz(NSEvent.mouseLocation)
        post(type: .leftMouseDown, at: p)
        post(type: .leftMouseUp, at: p)
        mouseIsDown = false
    }

    static func setDown(_ down: Bool) {
        let p = cocoaToQuartz(NSEvent.mouseLocation)
        if down && !mouseIsDown {
            post(type: .leftMouseDown, at: p)
            mouseIsDown = true
        } else if !down && mouseIsDown {
            post(type: .leftMouseUp, at: p)
            mouseIsDown = false
        }
    }

    static func cancel() {
        sizeUpWork?.cancel()
        sizeUpWork = nil
        if mouseIsDown { setDown(false) }
    }

    private static func postMouse(at quartz: CGPoint, dragging: Bool) {
        post(type: dragging ? .leftMouseDragged : .mouseMoved, at: quartz)
    }

    private static func post(type: CGEventType, at quartz: CGPoint) {
        guard LightroomAccessibility.isTrusted(prompt: false) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let button: CGMouseButton = (type == .mouseMoved) ? .left : .left
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: quartz, mouseButton: button) else { return }
        e.post(tap: .cghidEventTap)
    }

    /// Cocoa bottom-left → Quartz top-left of the primary display.
    private static func cocoaToQuartz(_ p: NSPoint) -> CGPoint {
        let primary = NSScreen.screens.first?.frame ?? .zero
        return CGPoint(x: p.x, y: primary.maxY - p.y)
    }
}
