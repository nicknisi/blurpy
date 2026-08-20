import Cocoa
import AVFoundation

/// Borderless, transparent, always-on-top Clippy-style popup: character floating
/// on the desktop with a comic speech bubble, center screen. Springs up from below
/// with overshoot, animates (two-frame finger wag for nedry, rock otherwise),
/// SPEAKS the message in Fred's verified male voice, slides back down on dismiss.
/// One at a time; extras queue (cap 3).
@MainActor
final class Popup {
    private var panel: NSPanel?
    private var queue: [(frames: [NSImage?], text: String)] = []
    private var dismissTimer: Timer?
    private var swapTimer: Timer?
    private let speaker = AVSpeechSynthesizer()
    private let maleVoice = AVSpeechSynthesisVoice(identifier: "com.apple.speech.synthesis.voice.Fred")

    func show(_ pitch: Pitch) {
        let imageName = pitch.cowboy ? "blurpy-cowboy" : "blurpy"
        enqueue(frames: [Self.bundledImage(imageName)], text: pitch.message)
        print("[blurpy] PITCH (\(pitch.id)\(pitch.cowboy ? ", cowboy" : "")): \(pitch.message)")
    }

    func showNedry(_ caption: String) {
        // ~/.config/blurpy/nedry.png overrides the bundled asset
        let overridePath = NSHomeDirectory() + "/.config/blurpy/nedry.png"
        let frame1 = (FileManager.default.fileExists(atPath: overridePath) ? NSImage(contentsOfFile: overridePath) : nil)
            ?? Self.bundledImage("nedry")
        enqueue(frames: [frame1, Self.bundledImage("nedry-wag")], text: caption)
        print("[blurpy] NEDRY: \(caption)")
    }

    private static func bundledImage(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }

    private func enqueue(frames: [NSImage?], text: String) {
        if panel != nil {
            if queue.count < 3 { queue.append((frames, text)) }
            return
        }
        present(frames: frames, text: text)
    }

    private func present(frames: [NSImage?], text: String) {
        let width: CGFloat = 430
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let maxTextW = width - 132 - 28
        let textH = ceil((text as NSString).boundingRect(
            with: NSSize(width: maxTextW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height)
        let height = max(150, textH + 26 + 56)

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

        let imageRect = NSRect(x: 10, y: 4, width: 120, height: 120)
        let imageView = NSImageView(frame: imageRect)
        imageView.image = frames[0]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = .init(width: 0, height: -2)
        imageView.shadow = shadow

        if frames.count > 1 {
            // two-frame animation: the finger wag
            let flag = BoolBox()
            swapTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
                MainActor.assumeIsolated {
                    flag.value.toggle()
                    imageView.image = frames[flag.value ? 0 : 1]
                }
            }
        } else {
            // single frame: rock the whole image, pivot near the bottom
            imageView.wantsLayer = true
            if let layer = imageView.layer {
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                layer.frame = imageRect
                let rock = CABasicAnimation(keyPath: "transform.rotation.z")
                rock.fromValue = -0.10
                rock.toValue = 0.10
                rock.duration = 0.25
                rock.autoreverses = true
                rock.repeatCount = .infinity
                rock.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(rock, forKey: "wag")
            }
        }
        click.addSubview(imageView)

        let bubble = BubbleView(frame: NSRect(x: 118, y: 26, width: width - 132, height: height - 44))
        click.addSubview(bubble)

        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = bubble.bounds.insetBy(dx: 14, dy: 12)
        label.font = font
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
        let final = NSPoint(x: screen.midX - width / 2, y: screen.midY - height / 2)
        panel.setFrameOrigin(NSPoint(x: final.x, y: screen.minY - height))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        print("[blurpy] popup on screen")
        self.panel = panel

        slide(panel, toY: final.y, duration: 0.5, ease: backOutEasing) { [weak panel] in
            if let panel { print("[blurpy] settled at \(panel.frame)") }
        }
        speak(text)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        swapTimer?.invalidate()
        speaker.stopSpeaking(at: .immediate)
        guard let panel, let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        slide(panel, toY: screen.minY - panel.frame.height, duration: 0.3, ease: easeInCubic) { [weak self] in
            panel.close()
            self?.panel = nil
            if let next = self?.queue.first {
                self?.queue.removeFirst()
                self?.present(frames: next.frames, text: next.text)
            }
        }
    }

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let voice = maleVoice ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en") && $0.gender == .male }
        print("[blurpy] voice: \(voice?.name ?? "none"), gender: \(voice?.gender == .male ? "male" : "unknown")")

        let prefix = text.range(of: #"^ah\s+ah\s+ah[.!?,]*\s*"#, options: [.regularExpression, .caseInsensitive])
        if let prefix {
            for _ in 0..<3 {
                let ah = AVSpeechUtterance(string: "Ah.")
                ah.voice = voice
                ah.rate = 0.34
                ah.pitchMultiplier = 0.82
                ah.postUtteranceDelay = 0.18
                speaker.speak(ah)
            }
            let rest = String(text[prefix.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                let body = AVSpeechUtterance(string: rest)
                body.voice = voice
                body.rate = 0.45
                body.pitchMultiplier = 0.90
                body.preUtteranceDelay = 0.20
                speaker.speak(body)
            }
        } else {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = 0.45
            utterance.pitchMultiplier = 0.90
            speaker.speak(utterance)
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

/// Mutable flag shared with a main-runloop timer block.
private final class BoolBox: @unchecked Sendable { var value = false }

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
