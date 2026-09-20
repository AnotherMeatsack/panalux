import AppKit

/// A small template counterpart of the app artwork: six knobs, three balls, one readout.
enum PanelStatusIcon {
    static func image(paused: Bool, connected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 23, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.5, width: 21, height: 17), xRadius: 3, yRadius: 3)
            body.lineWidth = 1.3
            body.stroke()
            for i in 0..<6 {
                NSBezierPath(ovalIn: NSRect(x: 4 + CGFloat(i) * 2.7, y: 13.7, width: 1.5, height: 1.5)).fill()
            }
            for i in 0..<3 {
                let ring = NSBezierPath(ovalIn: NSRect(x: 3.4 + CGFloat(i) * 6.1, y: 6.5, width: 4.5, height: 4.5))
                ring.lineWidth = 1.2
                ring.stroke()
            }
            if paused {
                NSBezierPath(rect: NSRect(x: 9, y: 3.2, width: 1.5, height: 2)).fill()
                NSBezierPath(rect: NSRect(x: 12, y: 3.2, width: 1.5, height: 2)).fill()
            } else {
                let readout = NSBezierPath(roundedRect: NSRect(x: 8, y: 3.2, width: 7, height: 1.6), xRadius: 0.8, yRadius: 0.8)
                connected ? readout.fill() : readout.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PanaLux panel"
        return image
    }
}
