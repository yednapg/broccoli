@preconcurrency import AppKit

/// The Minimal launcher is one continuous macOS Ultra Thick material. The surface persists
/// while the panel grows, so the search header and results never become separate cards.
@MainActor
final class LauncherMinimalMaterialSurfaceView: NSView {
    static let figmaBackgroundBlur = LauncherMinimalMetrics.figmaBackgroundBlur
    static let lightTintOpacity = LauncherMinimalMetrics.lightTintOpacity
    static let darkTintOpacity = LauncherMinimalMetrics.darkTintOpacity

    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private let contentHost = NSView()
    private weak var hostedContent: NSView?

    init(frame frameRect: NSRect = .zero, isDark: Bool) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = LauncherMinimalMetrics.cornerRadius
        layer?.cornerCurve = .circular
        layer?.borderWidth = 0
        layer?.borderColor = nil
        layer?.masksToBounds = true

        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .underWindowBackground
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        // Figma's dark variant is the same light Ultra Thick backdrop with an 85% black
        // wash above it. Keep only the material in Aqua; the AppKit content still follows
        // the launcher's requested appearance.
        materialView.appearance = NSAppearance(named: .aqua)
        addSubview(materialView)

        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = isDark
            ? NSColor.black.withAlphaComponent(Self.darkTintOpacity).cgColor
            : NSColor.white.withAlphaComponent(Self.lightTintOpacity).cgColor
        addSubview(tintView)

        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]
        addSubview(contentHost)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds
        contentHost.frame = bounds
        hostedContent?.frame = contentHost.bounds
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
