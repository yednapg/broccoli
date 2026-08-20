@preconcurrency import AppKit
import Carbon

final class ShortcutRecorderControl: NSView {
    private enum Metrics {
        static let intrinsicSize = NSSize(width: 132, height: 30)
        static let cornerRadius: CGFloat = 6
        static let horizontalTextInset: CGFloat = 8
    }

    var configuration: HotKeyConfiguration = .commandSpace {
        didSet {
            needsDisplay = true
            updateAccessibilityState()
        }
    }
    var onChange: ((HotKeyConfiguration) -> Bool)?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { Metrics.intrinsicSize }
    override var focusRingMaskBounds: NSRect { bounds }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override func mouseDown(with event: NSEvent) {
        _ = beginRecording()
    }

    /// Moves keyboard focus to the recorder and enters recording mode.
    ///
    /// The operation intentionally fails without changing state when the control is not in a
    /// window or cannot become first responder. This makes it safe for an external “Change…”
    /// button to call while the Settings hierarchy is being installed or removed.
    @discardableResult
    func beginRecording() -> Bool {
        guard let window, window.makeFirstResponder(self) else {
            setRecording(false)
            return false
        }
        setRecording(true)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            setRecording(false)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        guard carbonModifiers & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0 else {
            NSSound.beep()
            return
        }
        let newValue = HotKeyConfiguration(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        setRecording(false)
        if onChange?(newValue) != false {
            configuration = newValue
        } else {
            NSSound.beep()
            needsDisplay = true
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            needsDisplay = true
            setKeyboardFocusRingNeedsDisplay(bounds)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setRecording(false)
            setKeyboardFocusRingNeedsDisplay(bounds)
        }
        return resigned
    }

    override func accessibilityPerformPress() -> Bool {
        beginRecording()
    }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        ).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = isRecording ? 2 : 1
        let drawingBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(
            roundedRect: drawingBounds,
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
        let text = isRecording ? "Type shortcut…" : configuration.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let availableWidth = max(0, drawingBounds.width - Metrics.horizontalTextInset * 2)
        let textRect = NSRect(
            x: drawingBounds.midX - min(size.width, availableWidth) / 2,
            y: floor(drawingBounds.midY - size.height / 2),
            width: min(size.width, availableWidth),
            height: ceil(size.height)
        )
        text.draw(
            in: textRect,
            withAttributes: attributes
        )
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Global shortcut")
        focusRingType = .exterior
        updateAccessibilityState()
    }

    private func setRecording(_ value: Bool) {
        guard isRecording != value else {
            updateAccessibilityState()
            return
        }
        isRecording = value
        needsDisplay = true
        noteFocusRingMaskChanged()
        updateAccessibilityState()
    }

    private func updateAccessibilityState() {
        setAccessibilityValue(isRecording ? "Recording" : configuration.displayName)
        setAccessibilityHelp(
            isRecording
                ? "Recording. Press a shortcut, or Escape to cancel."
                : "Press to record a new global shortcut."
        )
    }
}
