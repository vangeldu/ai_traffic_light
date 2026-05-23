import AppKit
import Foundation

/// macOS App Icon per Apple HIG (June 2025):
/// - 1024×1024 square, full-bleed opaque background (system applies corner mask)
/// - Foreground only in safe zone; no custom outer radius, glow, or drop shadows
/// - Simple illustration (not a UI screenshot / floating widget replica)
enum AppIconRenderer {
    private static let canvas: CGFloat = 1024
    private static let safeInset: CGFloat = 112

    private struct Palette {
        static let bgTop = NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        static let bgBottom = NSColor(calibratedRed: 0.23, green: 0.23, blue: 0.26, alpha: 1)
        static let housing = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.88)
        static let red = NSColor(calibratedRed: 1, green: 0.27, blue: 0.23, alpha: 1)
        static let yellow = NSColor(calibratedRed: 1, green: 0.84, blue: 0.04, alpha: 1)
        static let green = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    }

    static func makeA5(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.cgContext.translateBy(x: 0, y: size)
            context.cgContext.scaleBy(x: 1, y: -1)
        }

        let scale = size / canvas
        func scaled(_ value: CGFloat) -> CGFloat { value * scale }

        drawBackground(scale: scale)
        drawForeground(scale: scale)

        NSGraphicsContext.current?.restoreGraphicsState()
        return image
    }

    static func makeBackgroundLayer(size: CGFloat = canvas) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.cgContext.translateBy(x: 0, y: size)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        drawBackground(scale: size / canvas)
        NSGraphicsContext.current?.restoreGraphicsState()
        return image
    }

    static func makeForegroundLayer(size: CGFloat = canvas) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.cgContext.translateBy(x: 0, y: size)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        drawForeground(scale: size / canvas)
        NSGraphicsContext.current?.restoreGraphicsState()
        return image
    }

    private static func drawBackground(scale: CGFloat) {
        func scaled(_ value: CGFloat) -> CGFloat { value * scale }
        let bounds = NSRect(x: 0, y: 0, width: scaled(canvas), height: scaled(canvas))
        let gradient = NSGradient(colors: [Palette.bgTop, Palette.bgBottom])!
        gradient.draw(in: bounds, angle: 90)
    }

    private static func drawForeground(scale: CGFloat) {
        func scaled(_ value: CGFloat) -> CGFloat { value * scale }

        let housingWidth = scaled(248)
        let housingHeight = scaled(520)
        let housingX = scaled((canvas - 248) / 2)
        let housingY = scaled((canvas - 520) / 2)

        let housing = NSBezierPath(
            roundedRect: NSRect(x: housingX, y: housingY, width: housingWidth, height: housingHeight),
            xRadius: scaled(124),
            yRadius: scaled(124)
        )
        Palette.housing.setFill()
        housing.fill()

        let centerX = scaled(canvas / 2)
        let lights: [(NSColor, CGFloat)] = [
            (Palette.red, canvas / 2 - 150),
            (Palette.yellow, canvas / 2),
            (Palette.green, canvas / 2 + 150)
        ]

        for (color, y) in lights {
            let radius = scaled(46)
            let dot = NSBezierPath(ovalIn: NSRect(x: centerX - radius, y: scaled(y) - radius,
                                                  width: radius * 2, height: radius * 2))
            color.setFill()
            dot.fill()
        }
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AppIconRenderer", code: 1)
        }
        try png.write(to: url)
    }
}

enum AppIconGeneratorCLI {
    static func main() {
        let iconset = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1])
            : URL(fileURLWithPath: "assets/AppIcon.iconset")
        let root = iconset.deletingLastPathComponent().deletingLastPathComponent()
        let layers = root.appendingPathComponent("assets/AppIcon/layers")

        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: layers, withIntermediateDirectories: true)

        let mapping: [(String, CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (name, size) in mapping {
            let image = AppIconRenderer.makeA5(size: size)
            try? AppIconRenderer.writePNG(image, to: iconset.appendingPathComponent(name))
        }

        try? AppIconRenderer.writePNG(AppIconRenderer.makeBackgroundLayer(), to: layers.appendingPathComponent("background-1024.png"))
        try? AppIconRenderer.writePNG(AppIconRenderer.makeForegroundLayer(), to: layers.appendingPathComponent("foreground-1024.png"))

        print("Generated HIG-compliant A5 icon set at \(iconset.path)")
        print("Layer exports for Icon Composer: \(layers.path)")
    }
}

AppIconGeneratorCLI.main()
