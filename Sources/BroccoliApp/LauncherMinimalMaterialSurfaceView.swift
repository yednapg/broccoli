@preconcurrency import AppKit

/// The Minimal launcher is one continuous surface: macOS Ultra Thick material in Light, an
/// opaque fill in Dark or when accessibility settings replace the material. The surface
/// persists while the panel grows, so the search header and results never become separate cards.
/// The material is clipped to the circular corner. The hairline is a sibling of that clip,
/// so the stroke is not eaten along the arcs.
@MainActor
final class LauncherMinimalMaterialSurfaceView: NSView {
    static let figmaBackgroundBlur = LauncherMinimalMetrics.figmaBackgroundBlur
    static let lightTintOpacity = LauncherMinimalMetrics.lightTintOpacity

    let materialClip = NSView()
    let rim = LauncherMinimalRimView()

    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let contentHost = NSView()
    private weak var hostedContent: NSView?

    init(
        frame frameRect: NSRect = .zero,
        isDark: Bool,
        increasedContrast: Bool = false,
        opaqueBackground: NSColor? = nil
    ) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.borderWidth = 0
        layer?.borderColor = nil
        layer?.shadowOpacity = 0
        layer?.masksToBounds = false

        materialClip.frame = bounds
        materialClip.autoresizingMask = [.width, .height]
        materialClip.wantsLayer = true
        materialClip.layer?.cornerRadius = LauncherMinimalMetrics.cornerRadius
        materialClip.layer?.cornerCurve = .circular
        materialClip.layer?.borderWidth = 0
        materialClip.layer?.borderColor = nil
        materialClip.layer?.masksToBounds = true
        addSubview(materialClip)

        materialView.frame = materialClip.bounds
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .underWindowBackground
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialClip.addSubview(materialView)

        tintView.frame = materialClip.bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        materialClip.addSubview(tintView)

        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]
        contentHost.wantsLayer = true
        // A rounded bounds clip, not a mask layer. A mask renders every row offscreen on
        // each frame of the height motion.
        contentHost.layer?.cornerCurve = .circular
        contentHost.layer?.masksToBounds = true
        addSubview(contentHost)

        rim.frame = bounds
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
        updateAppearance(
            isDark: isDark,
            increasedContrast: increasedContrast,
            opaqueBackground: opaqueBackground
        )
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let rimWidth = LauncherMinimalMetrics.rimWidth(forBackingScale: backingScale)
        let fillInset = LauncherMinimalMetrics.fillInset(forBackingScale: backingScale)
        // The fill stops at the hairline's inner edge, so the stroke sits outside it.
        materialClip.frame = bounds.insetBy(dx: fillInset, dy: fillInset)
        materialClip.layer?.cornerRadius = max(0, LauncherMinimalMetrics.cornerRadius - fillInset)
        rim.frame = bounds.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)
        rim.align(outerCornerRadius: LauncherMinimalMetrics.cornerRadius, borderWidth: 0)
        rim.isHidden = true
        materialView.frame = materialClip.bounds
        tintView.frame = materialClip.bounds
        contentHost.frame = bounds
        contentHost.layer?.cornerRadius = max(0, LauncherMinimalMetrics.cornerRadius - fillInset)
        hostedContent?.frame = contentHost.bounds
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    func updateAppearance(isDark: Bool, increasedContrast: Bool = false, opaqueBackground: NSColor? = nil) {
        materialView.isHidden = opaqueBackground != nil
        layer?.backgroundColor = nil
        rim.update(isDark: isDark, increasedContrast: increasedContrast)
        rim.isHidden = true
        rim.layer?.borderWidth = 0
        if let opaqueBackground {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                tintView.layer?.backgroundColor = opaqueBackground.cgColor
            }
            return
        }
        tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(Self.lightTintOpacity).cgColor
    }

    func setContentView(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = contentHost.bounds
        view.autoresizingMask = [.width, .height]
        contentHost.addSubview(view)
    }
}

/// One-pixel hairline drawn above the clipped Minimal material. A stroke on the clip
/// itself loses its outer pixels along the arcs.
@MainActor
final class LauncherMinimalRimView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = LauncherMinimalMetrics.cornerRadius
        layer?.cornerCurve = .circular
        layer?.masksToBounds = false
        align(outerCornerRadius: LauncherMinimalMetrics.cornerRadius, borderWidth: 0)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        superview?.needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        superview?.needsLayout = true
    }

    func update(isDark: Bool, increasedContrast: Bool) {
        isHidden = false
        let color = LauncherMinimalMetrics.rimColor(
            isDark: isDark,
            increasedContrast: increasedContrast
        ).cgColor
        if layer?.borderColor != color { layer?.borderColor = color }
    }

    func align(outerCornerRadius: CGFloat, borderWidth: CGFloat) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = max(scale, 1)
        layer?.borderWidth = borderWidth
        layer?.cornerRadius = max(0, outerCornerRadius - borderWidth / 2)
        layer?.masksToBounds = false
    }
}
