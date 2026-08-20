import Cocoa

/// Borderless, transparent, always-on-top Clippy-style popup: character floating
/// on the desktop with a comic speech bubble. Springs up from below the screen,
/// slides back down on dismiss. One at a time; extras queue (cap 3).
@MainActor
final class Popup {
    private var panel: NSPanel?
    private var queue: [(image: NSImage?, text: String)] = []
    private var dismissTimer: Timer?

    func show(_ pitch: Pitch) {
        let imageName = pitch.cowboy ? "blurpy-cowboy" : "blurpy"
        enqueue(image: Self.bundledImage(imageName), text: pitch.message)
        print("[blurpy] PITCH (\(pitch.id)\(pitch.cowboy ? ", cowboy" : "")): \(pitch.message)")
    }

    func showNedry(_ caption: String) {
        // ~/.config/blurpy/nedry.png overrides the bundled asset
        let overridePath = NSHomeDirectory() + "/.config/blurpy/nedry.png"
        let image = (FileManager.default.fileExists(atPath: overridePath) ? NSImage(contentsOfFile: overridePath) : nil)
            ?? Self.bundledImage("nedry")
        enqueue(image: image, text: caption)
        print("[blurpy] NEDRY: \(caption)")
    }

    private static func bundledImage(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }

    private func enqueue(image: NSImage?, text: String) {
        if panel != nil {
            if queue.count < 3 { queue.append((image, text)) }
            return
        }
        present(image: image, text: text)
    }

    private func present(image: NSImage?, text: String) {
        let width: CGFloat = 430
        let height: CGFloat = 210
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let click = ClickView { [weak self] in self?.dismiss() }
        click.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: 120, height: 120))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = .init(width: 0, height: -2)
        imageView.shadow = shadow
        click.addSubview(imageView)

        let bubble = BubbleView(frame: NSRect(x: 118, y: 26, width: width - 132, height: height - 44))
        click.addSubview(bubble)

        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = bubble.bounds.insetBy(dx: 14, dy: 12)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .black
        label.isBezeled = false
        label.isEditable = false
        label.backgroundColor = .clear
        bubble.addSubview(label)

        panel.contentView = click
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            print("[blurpy] no screen — popup swallowed")
            return
        }
        let final = NSPoint(x: screen.maxX - width - 24, y: screen.minY + 12)
        panel.setFrameOrigin(NSPoint(x: final.x, y: screen.minY - height))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        print("[blurpy] popup on screen")
        self.panel = panel

        slide(panel, toY: final.y, duration: 0.5, ease: backOutEasing) { [weak panel] in
            if let panel { print("[blurpy] settled at \(panel.frame)") }
        }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        guard let panel, let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        slide(panel, toY: screen.minY - panel.frame.height, duration: 0.3, ease: easeInCubic) { [weak self] in
            panel.close()
            self?.panel = nil
            if let next = self?.queue.first {
                self?.queue.removeFirst()
                self?.present(image: next.image, text: next.text)
            }
        }
    }

    /// Per-tick frame animation. NSWindow's animator proxy is unreliable on
    /// borderless panels — never trust it again.
    private func slide(_ panel: NSPanel, toY targetY: CGFloat, duration: TimeInterval, ease: @escaping @Sendable (Double) -> Double, then: @escaping @MainActor @Sendable () -> Void = {}) {
        let startY = panel.frame.minY
        let start = Date()
        // assumeIsolated is safe: timers scheduled here fire on the main runloop
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let timer = SendableTimer(timer: timer)
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: startY + (targetY - startY) * CGFloat(ease(t))))
                if t >= 1 { timer.timer.invalidate(); then() }
            }
        }
    }

}

/// Timer isn't Sendable; we know it's confined to the main runloop.
private struct SendableTimer: @unchecked Sendable { let timer: Timer }

/// Overshoot easing (back-out), for the springy entrance.
private func backOutEasing(_ t: Double) -> Double {
    let s = 1.70158 * 1.3
    let u = t - 1
    return 1 + (s + 1) * u * u * u + s * u * u
}

private func easeInCubic(_ t: Double) -> Double { t * t * t }

/// White comic speech bubble with a tail pointing down-left at the character.
private final class BubbleView: NSView {
    override func draw(_: NSRect) {
        let tailW: CGFloat = 22
        let inset: CGFloat = 1
        let body = NSRect(x: bounds.minX + inset, y: bounds.minY + inset, width: bounds.width - inset * 2, height: bounds.height - inset * 2)
        let path = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        // tail: from bottom edge, down-left toward blurpy, back to bottom edge
        path.move(to: NSPoint(x: bounds.minX + 30, y: bounds.minY + inset))
        path.line(to: NSPoint(x: bounds.minX - tailW + 14, y: bounds.minY - 16))
        path.line(to: NSPoint(x: bounds.minX + 56, y: bounds.minY + inset))
        path.close()
        NSColor.white.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

private final class ClickView: NSView {
    let onClick: () -> Void
    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with: NSEvent) { onClick() }
}
