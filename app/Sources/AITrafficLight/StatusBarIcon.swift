import AppKit

enum StatusBarIcon {
    private enum Light: CaseIterable {
        case red, yellow, green
    }

    private static let canvas: CGFloat = 18

    static func make(state: String) -> NSImage {
        let active = activeLight(for: state)
        let size = NSSize(width: canvas, height: canvas)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        // Match HTML/SVG: origin top-left, y grows downward.
        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.cgContext.translateBy(x: 0, y: canvas)
            context.cgContext.scaleBy(x: 1, y: -1)
        }

        NSColor.labelColor.withAlphaComponent(0.34).setStroke()
        let capsule = NSBezierPath(
            roundedRect: NSRect(x: 5.5, y: 1.5, width: 7, height: 15),
            xRadius: 3.5,
            yRadius: 3.5
        )
        capsule.lineWidth = 1
        capsule.stroke()

        let positions: [(Light, CGFloat)] = [
            (.red, 5),
            (.yellow, 9),
            (.green, 13)
        ]

        for (light, y) in positions {
            let radius: CGFloat = light == active ? 2.0 : 1.45
            let rect = NSRect(x: 9 - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let dot = NSBezierPath(ovalIn: rect)
            if light == active {
                NSColor.labelColor.setFill()
            } else {
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
            }
            dot.fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        image.isTemplate = true
        return image
    }

    private static func activeLight(for state: String) -> Light {
        switch state {
        case "running": return .red
        case "thinking": return .yellow
        default: return .green
        }
    }
}
