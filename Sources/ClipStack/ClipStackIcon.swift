import AppKit

/// A template image keeps the brand legible in light, dark, and selected menu bars.
enum ClipStackIcon {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let stack = NSBezierPath()
            stack.lineWidth = 1.5
            stack.lineCapStyle = .round
            stack.lineJoinStyle = .round
            stack.move(to: NSPoint(x: 8, y: 16))
            stack.line(to: NSPoint(x: 15.5, y: 16))
            stack.curve(to: NSPoint(x: 18, y: 13.5), controlPoint1: NSPoint(x: 17, y: 16), controlPoint2: NSPoint(x: 18, y: 15))
            stack.line(to: NSPoint(x: 18, y: 6))
            stack.stroke()

            let card = NSBezierPath(roundedRect: NSRect(x: 2, y: 1, width: 12, height: 13), xRadius: 2, yRadius: 2)
            card.lineWidth = 1.5
            card.stroke()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 12, width: 6, height: 3), xRadius: 1, yRadius: 1).fill()
            for (y, width): (CGFloat, CGFloat) in [(8, 6), (5, 4)] {
                NSBezierPath(roundedRect: NSRect(x: 5, y: y, width: width, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ClipStack 剪贴板历史"
        return image
    }
}
