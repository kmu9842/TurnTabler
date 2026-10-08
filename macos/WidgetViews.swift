import AppKit
import QuartzCore

final class WidgetNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var dismissPanels: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismissPanels?() }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var drag: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) { drag?(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PassiveImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class RotatingArtworkView: FlippedView {
    var image: NSImage?
    var pivot: NSPoint?
    var drawsDisc = false
    var drawsGroove = false
    var rotationRadians: CGFloat = 0 {
        didSet { if rotationRadians != oldValue { needsDisplay = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        if drawsDisc {
            context.addEllipse(in: bounds)
            context.clip()
            context.setFillColor(NSColor(calibratedWhite: 0.065, alpha: 1).cgColor)
            context.fill(bounds)
        }

        // AppKit owns the view's backing-layer geometry. Rotate only the drawing
        // coordinates, so layout, scaling and reparenting cannot move the pivot.
        let center = pivot ?? NSPoint(x: bounds.midX, y: bounds.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: rotationRadians)
        context.translateBy(x: -center.x, y: -center.y)
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if drawsGroove {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.125).cgColor)
            context.setLineWidth(0.45)
            context.addArc(center: center, radius: bounds.width / 2 - 6.6,
                           startAngle: -.pi / 2, endAngle: -.pi / 2 + 0.33, clockwise: false)
            context.strokePath()
        }
    }
}

final class GlassPanel: FlippedView {
    var radius: CGFloat = 9
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSGradient(colorsAndLocations: (.white.withAlphaComponent(0.08), 0),
                   (.white.withAlphaComponent(0.012), 0.25), (.clear, 0.75),
                   (.white.withAlphaComponent(0.06), 1))?.draw(in: path, angle: 90)
        NSColor.white.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 0.8; path.stroke()
    }
}

final class GlassSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        let path = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        NSColor.white.withAlphaComponent(0.04).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke(); path.lineWidth = 0.7; path.stroke()
        let fraction = CGFloat((doubleValue - minValue) / max(1, maxValue - minValue))
        NSColor.white.withAlphaComponent(0.44).setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.midY - 1, width: track.width * fraction, height: 2), xRadius: 1, yRadius: 1).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let rect = NSRect(x: knobRect.midX - 6, y: knobRect.midY - 8, width: 12, height: 16)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSGradient(starting: .white.withAlphaComponent(0.25), ending: .white.withAlphaComponent(0.05))?.draw(in: path, angle: 0)
        NSColor.white.withAlphaComponent(0.8).setStroke(); path.lineWidth = 0.8; path.stroke()
        NSColor.white.withAlphaComponent(0.65).setFill()
        NSRect(x: rect.midX - 0.5, y: rect.midY - 4, width: 1, height: 8).fill()
    }
}

final class FilmView: FlippedView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.045).setFill()
        for y in stride(from: CGFloat(0), to: bounds.height, by: 3) {
            NSRect(x: 0, y: y, width: bounds.width, height: 0.5).fill()
        }
    }
}

func radialMask(size: NSSize, locations: [NSNumber], opacities: [CGFloat]) -> CAGradientLayer {
    let mask = CAGradientLayer()
    mask.frame = NSRect(origin: .zero, size: size)
    mask.type = .radial
    mask.startPoint = CGPoint(x: 0.5, y: 0.5); mask.endPoint = CGPoint(x: 1, y: 1)
    mask.colors = opacities.map { NSColor.white.withAlphaComponent($0).cgColor }
    mask.locations = locations
    return mask
}
