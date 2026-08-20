@preconcurrency import AppKit
import BroccoliCore
import Foundation
@preconcurrency import QuickLookThumbnailing

private enum SearchFieldCommand {
    case up
    case down
    case execute
    case reveal
    case preferences
    case executeIndex(Int)
    case dismiss
}

enum LauncherNumericShortcut {
    static func row(for characters: String) -> Int? {
        guard let number = Int(characters) else { return nil }
        if number == 0 { return 9 }
        return (2...9).contains(number) ? number - 1 : nil
    }

    static func label(forRow row: Int) -> String {
        if row == 0 { return "↩" }
        if row == 9 { return "⌘0" }
        return "⌘\(row + 1)"
    }
}

struct LauncherScrollAccumulator {
    private(set) var accumulatedDeltaY: CGFloat = 0

    mutating func consume(
        deltaY: CGFloat,
        precise: Bool,
        began: Bool,
        ended: Bool
    ) -> [Bool] {
        if began { accumulatedDeltaY = 0 }
        accumulatedDeltaY += deltaY
        let threshold: CGFloat = precise ? 12 : 1
        let maximumSteps = precise ? 3 : 1
        var moves: [Bool] = []
        while abs(accumulatedDeltaY) >= threshold, moves.count < maximumSteps {
            let movesUp = accumulatedDeltaY > 0
            moves.append(movesUp)
            accumulatedDeltaY += movesUp ? -threshold : threshold
        }
        accumulatedDeltaY = min(threshold * 2, max(-threshold * 2, accumulatedDeltaY))
        if ended { accumulatedDeltaY = 0 }
        return moves
    }
}

enum LauncherSelection {
    static func nextRow(
        currentRow: Int,
        movingUp: Bool,
        results: [RankedResult]
    ) -> Int? {
        let selectable = results.indices.filter { results[$0].entry.kind != .status }
        guard !selectable.isEmpty else { return nil }
        if currentRow < 0 { return movingUp ? selectable.last : selectable.first }
        return movingUp
            ? selectable.last(where: { $0 < currentRow })
            : selectable.first(where: { $0 > currentRow })
    }

    static func preferredRow(
        preservingEntryID entryID: String?,
        in results: [RankedResult]
    ) -> Int? {
        if let entryID,
           let retainedRow = results.firstIndex(where: {
               $0.entry.id == entryID && $0.entry.kind != .status
           }) {
            return retainedRow
        }
        return results.firstIndex(where: { $0.entry.kind != .status })
    }
}

/// Frame calculations are intentionally independent from AppKit window mutation so the
/// launcher's screen position contract can be regression-tested. Result changes may alter
/// only the bottom edge; the top edge is invariant until the user reopens or repositions the
/// launcher.
enum LauncherPanelGeometry {
    static func resizing(_ frame: NSRect, toHeight height: CGFloat) -> NSRect {
        let height = max(0, height)
        return NSRect(
            x: frame.minX,
            y: frame.maxY - height,
            width: frame.width,
            height: height
        )
    }

    static func positionedFrame(
        in visibleFrame: NSRect,
        preferredWidth: CGFloat,
        height: CGFloat,
        verticalPosition: CGFloat
    ) -> NSRect {
        let width = min(preferredWidth, max(0, visibleFrame.width - 80))
        let height = max(0, height)
        let topInset = max(36, visibleFrame.height * verticalPosition)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - height - topInset,
            width: width,
            height: height
        )
    }
}

enum LauncherPreviewUpdateGuard {
    static func shouldApply(
        deliveredGeneration: Int,
        currentGeneration: Int,
        expectedRow: Int,
        selectedRow: Int,
        expectedEntryID: String,
        visibleEntryID: String?
    ) -> Bool {
        deliveredGeneration == currentGeneration
            && expectedRow == selectedRow
            && expectedEntryID == visibleEntryID
    }
}

private final class SendablePreviewImage: @unchecked Sendable {
    let value: NSImage

    init(_ value: NSImage) {
        self.value = value
    }
}

private final class LauncherSearchField: NSTextField {
    var onCommand: ((SearchFieldCommand) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            onCommand?(.preferences)
            return
        }
        if event.modifierFlags.contains(.command), [36, 76].contains(event.keyCode) {
            onCommand?(.reveal)
            return
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let row = LauncherNumericShortcut.row(for: characters) {
            onCommand?(.executeIndex(row))
            return
        }
        switch event.keyCode {
        case 125: onCommand?(.down)
        case 126: onCommand?(.up)
        case 36, 76: onCommand?(.execute)
        case 53: onCommand?(.dismiss)
        default: super.keyDown(with: event)
        }
    }
}

/// The Liquid Glass launcher uses a real AppKit search field so its magnifier, clear button,
/// placeholder color, editing rect, and accessibility semantics stay aligned with macOS.
/// Keyboard navigation is still handled by the controller's NSTextFieldDelegate methods and
/// the panel's key equivalents, just as it is for the legacy launcher field.
@MainActor
struct LauncherSearchGeometry {
    static let symbolSize: CGFloat = 24
    static let symbolTextGap: CGFloat = 14
    static let cancelSize: CGFloat = 18
    static let cancelTrailingInset: CGFloat = 2
    static let font = NSFont.systemFont(ofSize: 26, weight: .regular)

    let bounds: NSRect

    var searchButtonRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.midY - Self.symbolSize / 2,
            width: Self.symbolSize,
            height: Self.symbolSize
        )
    }

    var cancelButtonRect: NSRect {
        NSRect(
            x: bounds.maxX - Self.cancelTrailingInset - Self.cancelSize,
            y: bounds.midY - Self.cancelSize / 2,
            width: Self.cancelSize,
            height: Self.cancelSize
        )
    }

    var searchTextRect: NSRect {
        let leading = searchButtonRect.maxX + Self.symbolTextGap
        let trailing = cancelButtonRect.minX - 10
        let lineHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        return NSRect(
            x: leading,
            y: bounds.midY - lineHeight / 2,
            width: max(0, trailing - leading),
            height: lineHeight
        )
    }
}

final class LauncherNativeSearchFieldCell: NSSearchFieldCell {
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        LauncherSearchGeometry(bounds: rect).searchButtonRect
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        LauncherSearchGeometry(bounds: rect).searchTextRect
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        LauncherSearchGeometry(bounds: rect).cancelButtonRect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        searchTextRect(forBounds: rect)
    }

    override func edit(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: searchTextRect(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: searchTextRect(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

final class LauncherNativeSearchField: NSSearchField {
    override var searchButtonBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds).searchButtonRect,
            options: .alignAllEdgesNearest
        )
    }

    override var searchTextBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds).searchTextRect,
            options: .alignAllEdgesNearest
        )
    }

    override var cancelButtonBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds).cancelButtonRect,
            options: .alignAllEdgesNearest
        )
    }

    /// A borderless NSSearchField keeps the shared field editor at the full control bounds,
    /// even though its searchTextBounds correctly excludes the magnifier and cancel button.
    /// Constrain the editor's clip view to AppKit's own search-text rectangle so the caret,
    /// placeholder, and typed text never draw underneath either button.
    func alignFieldEditorToSearchTextBounds() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let textBounds = searchTextBounds.integral
        if let clipView = editor.superview as? NSClipView {
            clipView.frame = textBounds
            editor.frame = NSRect(origin: .zero, size: textBounds.size)
        } else {
            editor.frame = textBounds
        }
    }
}

@MainActor
enum LauncherNativeSearchFieldStyle {
    static func apply(to searchField: NSSearchField) {
        let cell = LauncherNativeSearchFieldCell(textCell: "")
        searchField.cell = cell
        searchField.placeholderString = "Search"
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.controlSize = .large
        searchField.font = LauncherSearchGeometry.font
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        if let magnifier = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular)) {
            magnifier.alignmentRect = NSRect(
                origin: .zero,
                size: NSSize(
                    width: LauncherSearchGeometry.symbolSize,
                    height: LauncherSearchGeometry.symbolSize
                )
            )
            cell.searchButtonCell?.image = magnifier
            cell.searchButtonCell?.imageScaling = .scaleProportionallyUpOrDown
        }
        if let cancel = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) {
            cancel.alignmentRect = NSRect(
                origin: .zero,
                size: NSSize(
                    width: LauncherSearchGeometry.cancelSize,
                    height: LauncherSearchGeometry.cancelSize
                )
            )
            cell.cancelButtonCell?.image = cancel
            cell.cancelButtonCell?.imageScaling = .scaleProportionallyUpOrDown
        }
        searchField.cell?.lineBreakMode = .byTruncatingTail
        searchField.setAccessibilityRole(.textField)
        searchField.setAccessibilitySubrole(.searchField)
    }
}

/// The complete Liquid Glass launcher surface.
///
/// Spotlight uses one adaptive lens: the empty capsule grows into the results panel without
/// introducing a second material layer. Keep the search field and result list inside this one
/// native effect so AppKit can derive luminance and color directly from the desktop. In
/// particular, do not place an `NSVisualEffectView` behind `NSGlassEffectView`; doing so makes
/// the glass sample the synthetic material instead of the user's wallpaper.
@MainActor
final class LauncherLiquidGlassSurfaceView: NSView {
    static let expandedCornerRadius: CGFloat = 29
    static let collapsedHeight: CGFloat = 58

    private let contentHost = NSView()
    private var hostedContent: NSView?
    private var fallbackEffect: NSVisualEffectView?

    init(frame frameRect: NSRect = .zero, interactive: Bool = true) {
        super.init(frame: frameRect)
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = Self.expandedCornerRadius
            glass.style = .regular
            glass.tintColor = nil
            if #available(macOS 27, *) { glass.effectIsInteractive = interactive }
            glass.contentView = contentHost
            addSubview(glass)
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.autoresizingMask = [.width, .height]
            effect.blendingMode = .behindWindow
            effect.material = .hudWindow
            effect.state = .active
            contentHost.frame = bounds
            contentHost.autoresizingMask = [.width, .height]
            effect.addSubview(contentHost)
            addSubview(effect)
            fallbackEffect = effect
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        contentHost.frame = bounds
        let radius = bounds.height <= Self.collapsedHeight + 0.5
            ? bounds.height / 2
            : Self.expandedCornerRadius
        if #available(macOS 26, *),
           let glass = subviews.compactMap({ $0 as? NSGlassEffectView }).first {
            glass.cornerRadius = radius
        }
        fallbackEffect?.wantsLayer = true
        fallbackEffect?.layer?.cornerRadius = radius
        fallbackEffect?.layer?.cornerCurve = .continuous
        fallbackEffect?.layer?.masksToBounds = true
    }

    func setContentView(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }
}

private final class LauncherPanel: NSPanel {
    var onCommand: ((SearchFieldCommand) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            onCommand?(.preferences)
            return true
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let row = LauncherNumericShortcut.row(for: characters) {
            onCommand?(.executeIndex(row))
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Every launcher result is already visible, so physically scrolling the table only creates
/// a few pixels of accidental travel from AppKit's clip-view bookkeeping. Consume wheel and
/// trackpad input and turn it into deterministic selection steps instead.
private final class LauncherResultsScrollView: NSScrollView {
    var onSelectionStep: ((Bool) -> Void)?
    private var accumulator = LauncherScrollAccumulator()

    override func scrollWheel(with event: NSEvent) {
        // A single momentum event can contain hundreds of points. Processing every implied
        // row synchronously caused long main-thread bursts (and made an edge feel like it was
        // still moving). Bound work per event while retaining a small residual for continuity.
        let moves = accumulator.consume(
            deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas,
            began: event.phase == .began,
            ended: event.phase == .ended || event.momentumPhase == .ended
        )
        for movesUp in moves {
            onSelectionStep?(movesUp)
        }
    }
}

/// The production launcher row used by both the live panel and its inert Settings preview.
/// Keeping one implementation prevents screenshot and interactive previews from drifting away
/// from the actual icon, typography, shortcut, selection, and accessibility treatment.
final class ResultRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("BroccoliResultRow")

    private let resultIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var titleTopConstraint: NSLayoutConstraint!
    private var titleCenterConstraint: NSLayoutConstraint!
    private var titleToShortcutConstraint: NSLayoutConstraint!
    private var subtitleToShortcutConstraint: NSLayoutConstraint!
    private var titleToEdgeConstraint: NSLayoutConstraint!
    private var subtitleToEdgeConstraint: NSLayoutConstraint!
    private var selected = false
    private var selectionColor = NSColor.controlAccentColor
    private var usesAdaptiveSelectionText = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        resultIcon.translatesAutoresizingMaskIntoConstraints = false
        resultIcon.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        shortcutLabel.alignment = .right
        addSubview(resultIcon)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(shortcutLabel)
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        titleCenterConstraint = titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        titleToShortcutConstraint = titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: shortcutLabel.leadingAnchor,
            constant: -12
        )
        subtitleToShortcutConstraint = subtitleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: shortcutLabel.leadingAnchor,
            constant: -12
        )
        titleToEdgeConstraint = titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -12
        )
        subtitleToEdgeConstraint = subtitleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -12
        )
        iconLeadingConstraint = resultIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        iconWidthConstraint = resultIcon.widthAnchor.constraint(equalToConstant: 40)
        iconHeightConstraint = resultIcon.heightAnchor.constraint(equalToConstant: 40)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: resultIcon.trailingAnchor,
            constant: 4
        )
        NSLayoutConstraint.activate([
            iconLeadingConstraint,
            resultIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,
            titleLeadingConstraint,
            titleTopConstraint,
            titleToShortcutConstraint,
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0),
            subtitleToShortcutConstraint,
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    func configure(
        result: RankedResult,
        icon: NSImage,
        confirmation: Bool,
        row: Int,
        selected: Bool,
        theme: LauncherThemeDescriptor
    ) {
        resultIcon.image = icon.isTemplate
            ? (icon.withSymbolConfiguration(.init(pointSize: 27, weight: .regular)) ?? icon)
            : icon
        titleLabel.stringValue = result.entry.title
        subtitleLabel.stringValue = confirmation
            ? "Press Return again to confirm"
            : result.entry.subtitle
        // Tahoe Spotlight keeps Liquid Glass rows deliberately quiet: one centered title per
        // result. Paths and categories made Broccoli look denser than the system surface and
        // weakened the wallpaper-derived material. Confirmation remains visible because it is
        // required interaction feedback rather than metadata.
        let showsSubtitle = confirmation || (
            theme.design != .liquidGlass
                && theme.showsSubtitles
                && !result.entry.subtitle.isEmpty
        )
        let showsShortcut = theme.showsShortcuts && result.entry.kind != .status
        subtitleLabel.isHidden = !showsSubtitle
        shortcutLabel.isHidden = !showsShortcut
        titleTopConstraint.isActive = showsSubtitle
        titleCenterConstraint.isActive = !showsSubtitle
        titleToShortcutConstraint.isActive = showsShortcut
        subtitleToShortcutConstraint.isActive = showsShortcut
        titleToEdgeConstraint.isActive = !showsShortcut
        subtitleToEdgeConstraint.isActive = !showsShortcut
        shortcutLabel.stringValue = LauncherNumericShortcut.label(forRow: row)
        selectionColor = theme.selectionColor
        usesAdaptiveSelectionText = theme.design == .liquidGlass
        let usesLiquidGlassLayout = theme.design == .liquidGlass
        iconLeadingConstraint.constant = usesLiquidGlassLayout ? 8 : 4
        let liquidIconSize: CGFloat = resultIcon.image?.isTemplate == true ? 34 : 38
        iconWidthConstraint.constant = usesLiquidGlassLayout ? liquidIconSize : 40
        iconHeightConstraint.constant = usesLiquidGlassLayout ? liquidIconSize : 40
        titleLeadingConstraint.constant = usesLiquidGlassLayout ? 10 : 4
        titleLabel.font = .systemFont(
            ofSize: 17,
            weight: theme.design == .liquidGlass ? .regular : .medium
        )
        layer?.cornerRadius = theme.resultSelectionCornerRadius
        setSelected(selected)
        setAccessibilityLabel(result.entry.title)
        setAccessibilityHelp(subtitleLabel.stringValue)
    }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        layer?.backgroundColor = selected ? selectionColor.cgColor : NSColor.clear.cgColor
        updateColors()
    }

    private func updateColors() {
        let highlighted = selected || backgroundStyle == .emphasized
        let selectedText = usesAdaptiveSelectionText
            ? NSColor.labelColor
            : NSColor.alternateSelectedControlTextColor
        titleLabel.textColor = highlighted ? selectedText : .labelColor
        subtitleLabel.textColor = highlighted
            ? selectedText.withAlphaComponent(0.82)
            : .secondaryLabelColor
        shortcutLabel.textColor = highlighted
            ? selectedText.withAlphaComponent(0.88)
            : .tertiaryLabelColor
        // SF Symbol action icons are template images. Let AppKit apply semantic label colors
        // in Light, Dark, and selected states; native full-color app/Settings icons stay intact.
        resultIcon.contentTintColor = resultIcon.image?.isTemplate == true
            ? (highlighted ? selectedText : .labelColor)
            : nil
    }
}

@MainActor
final class LauncherPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private static let panelWidth: CGFloat = 560
    private static let searchHeight: CGFloat = 58
    private static let maximumPreparedResultRows = 10
    private let panel: LauncherPanel
    private let legacySearchField = LauncherSearchField()
    private let nativeSearchField = LauncherNativeSearchField()
    private let liquidGlassSurface = LauncherLiquidGlassSurfaceView()
    private let modeBadge = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = LauncherResultsScrollView()
    private let headerDivider = NSBox()
    private let headerIcon = NSImageView()
    private let headerSuggestionLabel = NSTextField(labelWithString: "")
    private let preparedResultRows: [ResultRowView]
    private let iconCache: IconCache
    private let themeController = LauncherThemeController()
    private var theme: LauncherThemeDescriptor
    private let previewIcon = NSImageView()
    private let previewTitle = NSTextField(labelWithString: "")
    private let previewSubtitle = NSTextField(wrappingLabelWithString: "")
    private var previewMetadataTask: Task<Void, Never>?
    private var previewThumbnailRequest: QLThumbnailGenerator.Request?
    private var previewGeneration = 0
    private var retainedContentView: NSView?
    private var results: [RankedResult] = []
    private var confirmationEntryID: String?
    private var isProgrammaticallyHiding = false
    private var pendingAppearance: LauncherAppearancePreferences?
    private var appliedAppearance: LauncherAppearancePreferences?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var resultsTopConstraint: NSLayoutConstraint?
    private var resultsBottomConstraint: NSLayoutConstraint?
    private var searchTrailingConstraint: NSLayoutConstraint?
    private var headerSuggestionWidthConstraint: NSLayoutConstraint?
    private var defaultSearchLeadingConstraint: NSLayoutConstraint?
    private var modeSearchLeadingConstraint: NSLayoutConstraint?
    private var modeBadgeWidthConstraint: NSLayoutConstraint?
    private var currentMode: LauncherMode = .main
    private var presentationSessionActive = false
    /// A single match can stay in Spotlight's compact inline-suggestion state. As soon as
    /// there are multiple choices, open one stable results viewport so typing never hides
    /// suggestions that the user needs to distinguish.
    private var liquidResultsExpanded = false

    private var searchField: NSTextField {
        theme.design == .liquidGlass ? nativeSearchField : legacySearchField
    }

    var onQueryChanged: ((String) -> Void)?
    var onExecute: ((RankedResult) -> Void)?
    /// Runs for every completed launcher presentation, including dispatch paths that
    /// intentionally suppress `onDismiss` so the previous application is not reactivated.
    var onDidHide: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onCancel: (() -> Void)?
    var onReveal: ((RankedResult) -> Void)?
    var onPreferences: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    override init() {
        iconCache = IconCache()
        preparedResultRows = (0..<Self.maximumPreparedResultRows).map { _ in
            let row = ResultRowView()
            row.identifier = ResultRowView.identifier
            return row
        }
        theme = LauncherThemeController().descriptor(for: .defaults(design: .minimal))
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.searchHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureContent()
        iconCache.onIconLoaded = { [weak self] key in self?.reloadVisibleIcon(for: key) }
    }

    var isVisible: Bool { panel.isVisible }
    var isKeyWindow: Bool { panel.isKeyWindow }
    var visibilityIsolationWindow: NSWindow { panel }
    var query: String { searchField.stringValue }
    var preparedResultRowCount: Int { preparedResultRows.count }
    var searchAccessibilityLabel: String? { searchField.accessibilityLabel() }
    var resultsAccessibilityLabel: String? { tableView.accessibilityLabel() }
    var isContentViewAttached: Bool {
        panel.contentView != nil && panel.contentView === retainedContentView
    }
    var isSearchSurfaceWindowBacked: Bool { liquidGlassSurface.window === panel }
    var isResultViewportVisible: Bool { !scrollView.isHidden }
    var inlineSuggestionText: String? {
        headerSuggestionLabel.isHidden ? nil : headerSuggestionLabel.stringValue
    }
    var currentPanelHeight: CGFloat { panel.frame.height }

    func applyAppearance(
        _ preferences: LauncherAppearancePreferences,
        force: Bool = false
    ) {
        if panel.isVisible {
            guard force
                    || pendingAppearance != preferences
                    || (pendingAppearance == nil && appliedAppearance != preferences)
            else { return }
            // Never tear the shared field editor and table out of a live panel. Theme changes
            // are queued here and prepared as part of dismissal, before another hotkey can run.
            pendingAppearance = preferences
            return
        }
        guard force
                || appliedAppearance != preferences
                || theme.design != preferences.design
        else { return }
        applyAppearanceNow(preferences)
    }

    private func applyAppearanceNow(_ preferences: LauncherAppearancePreferences) {
        pendingAppearance = nil
        appliedAppearance = preferences
        theme = themeController.descriptor(for: preferences)
        panel.appearance = theme.appearance
        panel.hasShadow = theme.hasShadow
        tableView.rowHeight = theme.rowHeight
        // Resize the borderless window before installing the new constrained content tree.
        // Otherwise AppKit briefly solves the new theme inside the old theme's height and can
        // collapse the panel or emit broken-constraint state during fast theme changes.
        resizePanel(to: desiredPanelHeight(for: results.count), display: false)
        configureContent()
        if panel.isVisible { position(on: panel.screen) }
    }

    func setMode(_ mode: LauncherMode, initialQuery: String = "") {
        currentMode = mode
        liquidResultsExpanded = false
        confirmationEntryID = nil
        searchField.stringValue = initialQuery
        switch mode {
        case .main:
            searchField.placeholderString = theme.design == .liquidGlass ? "Search" : nil
        case .fileSearch: searchField.placeholderString = "Find files and folders"
        case .clipboard: searchField.placeholderString = "Search clipboard history"
        }
        updateModeChrome()
        focusSearchField()
    }

    func prepareIcons(for entries: [SearchEntry]) {
        iconCache.prewarm(entries)
    }

    func show(on screen: NSScreen?) {
        presentationSessionActive = true
        liquidResultsExpanded = false
        // Keep Liquid Glass window-backed while hidden. Reattaching the effect hierarchy in
        // the same transaction as orderFront leaves AppKit no committed backdrop in which to
        // prepare its glass sampling, so the global-hotkey presentation can appear opaque.
        if panel.contentView !== retainedContentView {
            panel.contentView = retainedContentView
        }
        searchField.stringValue = ""
        results = []
        tableView.reloadData()
        resetTableScrollPosition()
        updatePreview()
        updateResultsGeometry()
        resizePanel(to: desiredPanelHeight(for: 0), display: false)
        confirmationEntryID = nil
        onQueryChanged?("")
        position(on: screen ?? NSScreen.main ?? NSScreen.screens.first)
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
        DispatchQueue.main.async { [weak self] in
            self?.restoreSearchFocusIfVisible()
        }
    }

    /// App activation can finish after `show(on:)` returns. Reassert the panel and field
    /// responder once AppKit reports that Broccoli is active so the first keystroke is not
    /// lost to the previously frontmost application.
    func restoreSearchFocusIfVisible() {
        guard panel.isVisible else { return }
        if !panel.isKeyWindow { panel.makeKey() }
        focusSearchField()
    }

    func dismiss(notify: Bool = true) {
        guard panel.isVisible else {
            // A panel configured with hidesOnDeactivate can become non-visible just before
            // AppKit delivers its resign-key callback. Finish any queued restyle here so the
            // next hotkey only reattaches the already-prepared view hierarchy.
            if let pendingAppearance { applyAppearanceNow(pendingAppearance) }
            finishPresentationSession(notify: notify)
            return
        }
        previewMetadataTask?.cancel()
        previewMetadataTask = nil
        cancelPreviewThumbnailRequest()
        previewGeneration &+= 1
        isProgrammaticallyHiding = true
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        retainedContentView = panel.contentView
        if let pendingAppearance { applyAppearanceNow(pendingAppearance) }
        isProgrammaticallyHiding = false
        confirmationEntryID = nil
        finishPresentationSession(notify: notify)
    }

    private func finishPresentationSession(notify: Bool) {
        guard presentationSessionActive else { return }
        presentationSessionActive = false
        // Restore any temporarily hidden Broccoli windows before reactivating the app that
        // owned focus. This keeps Settings behind an external app, while allowing it to become
        // key again when Settings itself invoked the launcher.
        onDidHide?()
        if notify { onDismiss?() }
    }

    func apply(_ results: [RankedResult], preservingSelection: Bool = false) {
        let selectedEntryID: String? = if preservingSelection,
                                          self.results.indices.contains(tableView.selectedRow) {
            self.results[tableView.selectedRow].entry.id
        } else {
            nil
        }
        // Spotlight keeps its initial Liquid Glass presentation as a single search capsule.
        // Recent results remain available to the other designs and specialized modes, but the
        // main Liquid Glass launcher expands only after the user supplies a query.
        let suppressesEmptyMainResults = theme.design == .liquidGlass
            && currentMode == .main
            && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Search producers already honor the configured limit. Clamp defensively here as
        // well so a malformed or streaming producer can never create a scrollable viewport.
        self.results = suppressesEmptyMainResults
            ? []
            : Array(results.prefix(theme.visibleResultCount))
        updateLiquidPresentationState()
        if !self.results.contains(where: { $0.entry.id == confirmationEntryID }) {
            confirmationEntryID = nil
        }
        resetTableScrollPosition()
        tableView.reloadData()
        if let preferredRow = LauncherSelection.preferredRow(
            preservingEntryID: selectedEntryID,
            in: self.results
        ) {
            tableView.selectRowIndexes(IndexSet(integer: preferredRow), byExtendingSelection: false)
            resetTableScrollPosition()
        } else {
            tableView.deselectAll(nil)
            resetTableScrollPosition()
        }
        refreshSelectionAppearance()
        updatePreview()
        updateHeaderIcon()
        updateHeight()
    }

    func showConfirmation(for entryID: String) {
        confirmationEntryID = entryID
        tableView.reloadData()
    }

    func clearConfirmation() {
        guard confirmationEntryID != nil else { return }
        confirmationEntryID = nil
        tableView.reloadData()
    }

    func showError(_ error: Error, automationRelated: Bool) {
        dismiss(notify: false)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Broccoli couldn’t run that action"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if automationRelated { alert.addButton(withTitle: "Open Privacy Settings") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func confirmAutomationFirstUse(actionTitle: String) -> Bool {
        dismiss(notify: false)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Automation Permission Required"
        alert.informativeText = "To run “\(actionTitle),” Broccoli sends a fixed, audited Apple Event to macOS System Events. Continue to show the macOS permission prompt."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showAutomationDenied(actionTitle: String) {
        dismiss(notify: false)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(actionTitle)” Needs Automation Access"
        alert.informativeText = "macOS has denied Broccoli permission to control System Events. The action was not run. You can enable Broccoli in Privacy & Security settings."
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAutomationPrivacySettings()
        }
    }

    func showAutomationUnavailable(actionTitle: String) {
        dismiss(notify: false)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(actionTitle)” Is Unavailable"
        alert.informativeText = "macOS System Events is not available right now. Broccoli did not run the action."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func openAutomationPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row), preparedResultRows.indices.contains(row) else {
            return nil
        }
        // The launcher displays at most ten rows. Give each row index a permanent view so the
        // first keystroke never allocates AppKit controls or installs Auto Layout constraints.
        let view = preparedResultRows[row]
        let result = results[row]
        view.configure(
            result: result,
            icon: iconCache.image(for: result.entry),
            confirmation: confirmationEntryID == result.entry.id,
            row: row,
            selected: tableView.selectedRow == row,
            theme: theme
        )
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        confirmationEntryID = nil
        refreshSelectionAppearance()
        updatePreview()
        updateHeaderIcon()
        onSelectionChanged?()
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        results.indices.contains(row) && results[row].entry.kind != .status
    }

    func controlTextDidChange(_ obj: Notification) {
        confirmationEntryID = nil
        if searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liquidResultsExpanded = false
        }
        onQueryChanged?(searchField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            handle(.up)
        case #selector(NSResponder.moveDown(_:)):
            handle(.down)
        case #selector(NSResponder.insertNewline(_:)):
            handle(NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .reveal : .execute)
        case #selector(NSResponder.cancelOperation(_:)):
            handle(.dismiss)
        default:
            return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isProgrammaticallyHiding { dismiss() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSearchField()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = "Broccoli Launcher"
        panel.setAccessibilityLabel("Broccoli Launcher")
        panel.appearance = theme.appearance
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Resignation is handled explicitly by windowDidResignKey. Automatic panel hiding can
        // happen before that delegate callback and leave isVisible out of sync with the launch
        // session, causing the next global shortcut to restore an old app instead of opening.
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.delegate = self
        panel.onCommand = { [weak self] command in self?.handle(command) }
    }

    private func configureContent() {
        headerSuggestionWidthConstraint?.isActive = false
        headerSuggestionWidthConstraint = nil
        legacySearchField.removeFromSuperview()
        nativeSearchField.removeFromSuperview()
        liquidGlassSurface.removeFromSuperview()
        modeBadge.removeFromSuperview()
        scrollView.removeFromSuperview()
        headerDivider.removeFromSuperview()
        headerIcon.removeFromSuperview()
        headerSuggestionLabel.removeFromSuperview()
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalToConstant: theme.width).isActive = true
        contentHeightConstraint?.isActive = false
        let contentHeightConstraint = content.heightAnchor.constraint(
            equalToConstant: desiredPanelHeight(for: results.count)
        )
        contentHeightConstraint.isActive = true
        self.contentHeightConstraint = contentHeightConstraint
        // NSWindow derives a fitting size from constraints installed directly below its
        // content view. Yosemite's effect view previously became that constrained root, so
        // AppKit repeatedly collapsed the 432-point panel to the search field's 70-point
        // minimum. Keep the window boundary frame-based and put all constrained content one
        // level below it. The host has no intrinsic size and always follows the panel frame.
        let host = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]

        let surface: NSView
        switch theme.surface {
        case .glass:
            if #available(macOS 26, *) {
                liquidGlassSurface.setContentView(content)
                surface = liquidGlassSurface
            } else {
                let fallback = NSView()
                install(content, in: fallback)
                surface = fallback
            }
        case .vibrancy, .classic:
            let effect = NSVisualEffectView()
            effect.blendingMode = .behindWindow
            effect.state = .active
            switch theme.surface {
            case .classic: effect.material = .sidebar
            default: effect.material = .hudWindow
            }
            install(content, in: effect)
            surface = effect
        case .opaque:
            let backdrop = NSView()
            install(content, in: backdrop)
            surface = backdrop
        }
        surface.frame = host.bounds
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        if theme.surface != .glass {
            surface.wantsLayer = true
            surface.layer?.backgroundColor = theme.surface == .opaque
                ? theme.backgroundColor.cgColor
                : nil
            surface.layer?.cornerRadius = theme.cornerRadius
            surface.layer?.cornerCurve = .continuous
            surface.layer?.borderWidth = theme.design == .minimal ? 0 : 1
            surface.layer?.borderColor = theme.design == .minimal ? nil : theme.borderColor.cgColor
            surface.layer?.masksToBounds = true
        }
        host.addSubview(surface)
        retainedContentView = host
        // A hidden NSWindow may safely retain its content hierarchy. Native glass needs this
        // persistent window association so its backdrop is ready before the next hotkey.
        panel.contentView = host

        let usesNativeSearch = theme.design == .liquidGlass
        let searchField = self.searchField
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = nil
        searchField.textColor = .labelColor
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.usesSingleLineMode = true
        searchField.focusRingType = .none
        if usesNativeSearch {
            LauncherNativeSearchFieldStyle.apply(to: nativeSearchField)
            nativeSearchField.font = .systemFont(ofSize: theme.searchFontSize, weight: .regular)
        } else {
            legacySearchField.font = .systemFont(ofSize: theme.searchFontSize, weight: .regular)
        }
        searchField.setAccessibilityLabel("Search Broccoli")
        searchField.setAccessibilityHelp("Type to search applications, settings, and actions")
        searchField.delegate = self
        legacySearchField.onCommand = { [weak self] command in self?.handle(command) }
        content.addSubview(searchField)
        panel.initialFirstResponder = searchField

        modeBadge.translatesAutoresizingMaskIntoConstraints = false
        modeBadge.font = .systemFont(ofSize: 12, weight: .semibold)
        modeBadge.alignment = .center
        modeBadge.textColor = .secondaryLabelColor
        modeBadge.wantsLayer = true
        modeBadge.layer?.cornerRadius = 8
        modeBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        content.addSubview(modeBadge)

        if tableView.tableColumns.isEmpty {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
        }
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = theme.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: theme.rowSpacing)
        // The custom ResultRowView owns selection chrome for every design; full-width table
        // geometry keeps its rounded selection aligned with each theme's result insets.
        tableView.style = theme.resultTableStyle
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.setAccessibilityLabel("Search results")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        // Bottom breathing room is already part of desiredPanelHeight. Applying it here too
        // makes the document slightly taller than the viewport and causes the visible jump.
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.onSelectionStep = { [weak self] movesUp in
            self?.handle(movesUp ? .up : .down)
        }
        content.addSubview(scrollView)
        let resultsChrome: NSView = scrollView
        let hasResults = presentsResultViewport
        let hasLiquidSuggestionIcon = presentsLiquidSuggestionIcon
        let hasLiquidInlineSuggestion = presentsLiquidInlineSuggestion
        let resultsTopConstraint = resultsChrome.topAnchor.constraint(
            equalTo: content.topAnchor,
            constant: theme.searchHeight + (hasResults ? theme.resultTopInset : 0)
        )
        let resultsBottomConstraint = resultsChrome.bottomAnchor.constraint(
            equalTo: content.bottomAnchor,
            constant: hasResults ? -theme.resultBottomInset : 0
        )
        self.resultsTopConstraint = resultsTopConstraint
        self.resultsBottomConstraint = resultsBottomConstraint
        scrollView.isHidden = !hasResults
        let searchChrome: NSView = searchField
        headerDivider.boxType = .separator
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.isHidden = !hasResults || theme.design != .liquidGlass
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        headerIcon.imageScaling = .scaleProportionallyUpOrDown
        headerIcon.isHidden = !(hasResults || hasLiquidSuggestionIcon)
        headerSuggestionLabel.translatesAutoresizingMaskIntoConstraints = false
        headerSuggestionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        headerSuggestionLabel.textColor = .secondaryLabelColor
        headerSuggestionLabel.alignment = .right
        headerSuggestionLabel.lineBreakMode = .byTruncatingTail
        headerSuggestionLabel.maximumNumberOfLines = 1
        headerSuggestionLabel.setAccessibilityLabel("Suggested result")
        headerSuggestionLabel.isHidden = !hasLiquidInlineSuggestion
        content.addSubview(headerDivider)
        content.addSubview(headerSuggestionLabel)
        content.addSubview(headerIcon)
        updateInlineSuggestionContent()
        let searchTrailingInset = liquidSearchTrailingInset(
            hasResults: hasResults,
            hasSuggestionIcon: hasLiquidSuggestionIcon
        )
        let searchTrailingConstraint = searchChrome.trailingAnchor.constraint(
            equalTo: content.trailingAnchor,
            constant: -searchTrailingInset
        )
        self.searchTrailingConstraint = searchTrailingConstraint
        var constraints = [
            searchTrailingConstraint,
            searchChrome.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.searchVerticalInset),
            searchChrome.heightAnchor.constraint(equalToConstant: theme.searchHeight - theme.searchVerticalInset * 2),
            resultsChrome.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: theme.resultHorizontalInset),
            resultsTopConstraint,
            resultsBottomConstraint,
            modeBadge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: theme.searchHorizontalInset),
            modeBadge.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),
            modeBadge.heightAnchor.constraint(equalToConstant: 26),
            headerDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            headerDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            headerDivider.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.searchHeight - 1),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),
            headerIcon.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            headerIcon.centerYAnchor.constraint(equalTo: content.topAnchor, constant: theme.searchHeight / 2),
            headerIcon.widthAnchor.constraint(equalToConstant: 28),
            headerIcon.heightAnchor.constraint(equalToConstant: 28),
            headerSuggestionLabel.trailingAnchor.constraint(equalTo: headerIcon.leadingAnchor, constant: -10),
            headerSuggestionLabel.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor),
            headerSuggestionLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: content.centerXAnchor,
                constant: 8
            ),
        ]
        let headerSuggestionWidthConstraint = headerSuggestionLabel.widthAnchor.constraint(
            equalToConstant: inlineSuggestionWidth
        )
        constraints.append(headerSuggestionWidthConstraint)
        self.headerSuggestionWidthConstraint = headerSuggestionWidthConstraint
        let modeBadgeWidthConstraint = modeBadge.widthAnchor.constraint(equalToConstant: 54)
        constraints.append(modeBadgeWidthConstraint)
        self.modeBadgeWidthConstraint = modeBadgeWidthConstraint
        modeSearchLeadingConstraint = searchChrome.leadingAnchor.constraint(
            equalTo: modeBadge.trailingAnchor,
            constant: 10
        )
        defaultSearchLeadingConstraint = searchChrome.leadingAnchor.constraint(
            equalTo: content.leadingAnchor,
            constant: theme.searchHorizontalInset
        )
        if theme.showsPreview {
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            let preview = makePreviewView()
            content.addSubview(divider)
            content.addSubview(preview)
            constraints += [
                scrollView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
                divider.widthAnchor.constraint(equalToConstant: 1),
                divider.topAnchor.constraint(equalTo: scrollView.topAnchor),
                divider.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                preview.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
                preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -theme.resultHorizontalInset),
                preview.topAnchor.constraint(equalTo: scrollView.topAnchor),
                preview.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                preview.widthAnchor.constraint(equalToConstant: theme.previewWidth),
            ]
        } else {
            constraints.append(resultsChrome.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -theme.resultHorizontalInset
            ))
        }
        NSLayoutConstraint.activate(constraints)
        updateModeChrome()
        tableView.rowHeight = theme.rowHeight
        tableView.reloadData()
        resetTableScrollPosition()
        refreshSelectionAppearance()
        updatePreview()
        updateHeaderIcon()
    }

    private func install(_ content: NSView, in container: NSView) {
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func handle(_ command: SearchFieldCommand) {
        switch command {
        case .up:
            revealCompactLiquidResultsIfNeeded()
            guard let row = LauncherSelection.nextRow(
                currentRow: tableView.selectedRow,
                movingUp: true,
                results: results
            ) else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            resetTableScrollPosition()
        case .down:
            revealCompactLiquidResultsIfNeeded()
            guard let row = LauncherSelection.nextRow(
                currentRow: tableView.selectedRow,
                movingUp: false,
                results: results
            ) else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            resetTableScrollPosition()
        case .execute:
            let row = max(0, tableView.selectedRow)
            guard results.indices.contains(row) else { return }
            onExecute?(results[row])
        case .reveal:
            let row = max(0, tableView.selectedRow)
            guard results.indices.contains(row) else { return }
            onReveal?(results[row])
        case .preferences:
            onPreferences?()
        case .executeIndex(let row):
            guard results.indices.contains(row), results[row].entry.kind != .status else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            refreshSelectionAppearance()
            onExecute?(results[row])
        case .dismiss:
            if let onCancel { onCancel() } else { dismiss() }
        }
    }

    private func focusSearchField() {
        guard panel.isVisible else { return }
        guard panel.makeFirstResponder(searchField) else { return }
        nativeSearchField.alignFieldEditorToSearchTextBounds()
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = .labelColor
        editor.textColor = .labelColor
        editor.backgroundColor = .clear
        editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
    }

    private func updateModeChrome() {
        defaultSearchLeadingConstraint?.isActive = false
        modeSearchLeadingConstraint?.isActive = false

        switch currentMode {
        case .main:
            modeBadge.isHidden = true
            defaultSearchLeadingConstraint?.isActive = true
            searchField.placeholderString = theme.design == .liquidGlass ? "Search Broccoli" : nil
        case .fileSearch:
            modeBadge.stringValue = "Files"
            modeBadgeWidthConstraint?.constant = 54
            modeBadge.isHidden = false
            modeSearchLeadingConstraint?.isActive = true
            searchField.placeholderString = "Search names and paths"
        case .clipboard:
            modeBadge.stringValue = "Clipboard"
            modeBadgeWidthConstraint?.constant = 78
            modeBadge.isHidden = false
            modeSearchLeadingConstraint?.isActive = true
            searchField.placeholderString = "Filter history"
        }
        if theme.design == .liquidGlass, let placeholder = searchField.placeholderString {
            nativeSearchField.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .font: LauncherSearchGeometry.font,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        }
    }

    private func updateHeight() {
        updateResultsGeometry()
        resizePanel(to: desiredPanelHeight(for: results.count), display: true)
    }

    private func desiredPanelHeight(for resultCount: Int) -> CGFloat {
        if theme.design == .liquidGlass, currentMode == .main {
            guard presentsResultViewport else { return theme.searchHeight }
            // Once opened, use one fixed result capacity. The panel therefore grows once and
            // keeps its top and bottom edges steady while asynchronous result sets change.
            return theme.panelHeight(resultCount: theme.visibleResultCount)
        }
        return theme.panelHeight(resultCount: resultCount)
    }

    private var presentsResultViewport: Bool {
        guard !results.isEmpty else { return false }
        guard theme.design == .liquidGlass, currentMode == .main else { return true }
        return liquidResultsExpanded
    }

    private var presentsLiquidSuggestionIcon: Bool {
        theme.design == .liquidGlass
            && currentMode == .main
            && !results.isEmpty
            && !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var presentsLiquidInlineSuggestion: Bool {
        theme.design == .liquidGlass
            && currentMode == .main
            && !presentsResultViewport
            && results.count == 1
            && !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inlineSuggestionWidth: CGFloat {
        guard presentsLiquidInlineSuggestion else { return 0 }
        return min(180, ceil(headerSuggestionLabel.intrinsicContentSize.width))
    }

    private func liquidSearchTrailingInset(
        hasResults: Bool,
        hasSuggestionIcon: Bool
    ) -> CGFloat {
        guard theme.design == .liquidGlass, hasResults || hasSuggestionIcon else {
            return theme.searchHorizontalInset
        }
        guard presentsLiquidInlineSuggestion else { return 64 }
        return 76 + inlineSuggestionWidth
    }

    private func updateInlineSuggestionContent() {
        guard presentsLiquidInlineSuggestion, let result = results.first else {
            headerSuggestionLabel.stringValue = ""
            headerSuggestionLabel.isHidden = true
            headerSuggestionWidthConstraint?.constant = 0
            return
        }
        headerSuggestionLabel.stringValue = result.entry.title
        headerSuggestionLabel.isHidden = false
        headerSuggestionWidthConstraint?.constant = inlineSuggestionWidth
    }

    private func updateLiquidPresentationState() {
        guard theme.design == .liquidGlass, currentMode == .main else { return }
        guard !searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else {
            liquidResultsExpanded = false
            return
        }
        // One match can be named inline. Multiple matches must be visible immediately; hiding
        // them for the first few characters makes the launcher look empty while search works.
        if results.count > 1 {
            liquidResultsExpanded = true
        }
    }

    private func revealCompactLiquidResultsIfNeeded() {
        guard theme.design == .liquidGlass,
              currentMode == .main,
              !liquidResultsExpanded,
              results.count > 1
        else { return }
        liquidResultsExpanded = true
        updateHeight()
    }

    private func resetTableScrollPosition() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateResultsGeometry() {
        let hasResults = presentsResultViewport
        resultsTopConstraint?.constant = theme.searchHeight
            + (hasResults ? theme.resultTopInset : 0)
        resultsBottomConstraint?.constant = hasResults ? -theme.resultBottomInset : 0
        scrollView.isHidden = !hasResults
        headerDivider.isHidden = !hasResults || theme.design != .liquidGlass
        headerIcon.isHidden = !(hasResults || presentsLiquidSuggestionIcon)
        updateInlineSuggestionContent()
        searchTrailingConstraint?.constant = -liquidSearchTrailingInset(
            hasResults: hasResults,
            hasSuggestionIcon: presentsLiquidSuggestionIcon
        )
        updateHeaderIcon()
    }

    private func resizePanel(to height: CGFloat, display: Bool) {
        contentHeightConstraint?.constant = height
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: height)
        // AppKit cannot interpolate a borderless window's native glass backdrop and its
        // Auto Layout content as one coherent shape. Animating the frame made the bottom edge
        // lag behind the rows and produced a rubbery flash when results appeared. Spotlight's
        // state change reads as a direct material reconfiguration, so commit it atomically.
        panel.setFrame(frame, display: display)
        // Keep the frame-based window root synchronized with the borderless panel. This also
        // commits correct native-glass geometry before the hidden panel is ordered front.
        let contentFrame = NSRect(origin: .zero, size: frame.size)
        retainedContentView?.frame = contentFrame
        panel.contentView?.frame = contentFrame
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func refreshSelectionAppearance() {
        guard tableView.numberOfColumns > 0 else { return }
        for row in 0..<results.count {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultRowView)?
                .setSelected(row == tableView.selectedRow)
        }
    }

    private func reloadVisibleIcon(for key: String) {
        guard panel.isVisible else { return }
        let rows = IndexSet(results.indices.filter { results[$0].entry.iconKey == key })
        guard !rows.isEmpty else { return }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        refreshSelectionAppearance()
        updatePreview()
        updateHeaderIcon()
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let height = max(theme.searchHeight, panel.frame.height)
        let frame = LauncherPanelGeometry.positionedFrame(
            in: screen.visibleFrame,
            preferredWidth: theme.width,
            height: height,
            verticalPosition: theme.verticalPosition
        )
        panel.setFrame(frame, display: false)
    }

    private func makePreviewView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        previewIcon.translatesAutoresizingMaskIntoConstraints = false
        previewIcon.imageScaling = .scaleProportionallyUpOrDown
        previewTitle.translatesAutoresizingMaskIntoConstraints = false
        previewTitle.font = .systemFont(ofSize: 19, weight: .semibold)
        previewTitle.alignment = .center
        previewTitle.lineBreakMode = .byTruncatingTail
        previewSubtitle.translatesAutoresizingMaskIntoConstraints = false
        previewSubtitle.font = .systemFont(ofSize: 12)
        previewSubtitle.textColor = .secondaryLabelColor
        previewSubtitle.alignment = .center
        previewSubtitle.maximumNumberOfLines = 5
        view.addSubview(previewIcon)
        view.addSubview(previewTitle)
        view.addSubview(previewSubtitle)
        NSLayoutConstraint.activate([
            previewIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewIcon.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            previewIcon.widthAnchor.constraint(equalToConstant: 64),
            previewIcon.heightAnchor.constraint(equalToConstant: 64),
            previewTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            previewTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            previewTitle.topAnchor.constraint(equalTo: previewIcon.bottomAnchor, constant: 8),
            previewSubtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            previewSubtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            previewSubtitle.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 4),
        ])
        return view
    }

    private func updateHeaderIcon() {
        guard theme.design == .liquidGlass else {
            headerIcon.image = nil
            headerIcon.isHidden = true
            return
        }
        let selectedRow = tableView.selectedRow
        let row = results.indices.contains(selectedRow) ? selectedRow : results.indices.first
        guard let row else {
            headerIcon.image = nil
            headerIcon.isHidden = true
            return
        }
        headerIcon.image = iconCache.image(for: results[row].entry)
        headerIcon.contentTintColor = headerIcon.image?.isTemplate == true ? .labelColor : nil
        headerIcon.isHidden = false
    }

    private func updatePreview() {
        guard theme.showsPreview else { return }
        previewMetadataTask?.cancel()
        previewMetadataTask = nil
        cancelPreviewThumbnailRequest()
        previewGeneration &+= 1
        let generation = previewGeneration
        let selectedRow = tableView.selectedRow
        let row = results.indices.contains(selectedRow)
            ? selectedRow
            : (results.count == 1 ? 0 : -1)
        guard results.indices.contains(row) else {
            previewIcon.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: nil)
            previewTitle.stringValue = "Broccoli"
            previewSubtitle.stringValue = "Select a result to preview it"
            return
        }
        let result = results[row]
        previewIcon.image = iconCache.image(for: result.entry)
        previewTitle.stringValue = result.entry.title
        previewSubtitle.stringValue = result.entry.subtitle

        guard case .file(let path, let isDirectory) = result.entry.target else { return }
        previewSubtitle.stringValue = isDirectory
            ? "Folder\n\(result.entry.subtitle)"
            : "Loading file details…\n\(result.entry.subtitle)"
        if !isDirectory {
            requestPreviewThumbnail(
                path: path,
                row: row,
                entryID: result.entry.id,
                generation: generation
            )
        }
        previewMetadataTask = Task { [weak self] in
            let details = await Task.detached(priority: .utility) {
                Self.filePreviewDetails(path: path, isDirectory: isDirectory)
            }.value
            guard !Task.isCancelled, let self,
                  LauncherPreviewUpdateGuard.shouldApply(
                    deliveredGeneration: generation,
                    currentGeneration: self.previewGeneration,
                    expectedRow: row,
                    selectedRow: self.tableView.selectedRow,
                    expectedEntryID: result.entry.id,
                    visibleEntryID: self.results.indices.contains(row)
                        ? self.results[row].entry.id
                        : nil
                  ) else { return }
            self.previewSubtitle.stringValue = details
        }
    }

    private func requestPreviewThumbnail(
        path: String,
        row: Int,
        entryID: String,
        generation: Int
    ) {
        let scale = panel.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: NSSize(width: 176, height: 176),
            scale: scale,
            representationTypes: .thumbnail
        )
        previewThumbnailRequest = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            [weak self] representation, _ in
            guard let representation else { return }
            let image = SendablePreviewImage(NSImage(
                cgImage: representation.cgImage,
                size: NSSize(width: 88, height: 88)
            ))
            Task { @MainActor [weak self, image] in
                guard let self,
                      self.previewThumbnailRequest === request,
                      LauncherPreviewUpdateGuard.shouldApply(
                        deliveredGeneration: generation,
                        currentGeneration: self.previewGeneration,
                        expectedRow: row,
                        selectedRow: self.tableView.selectedRow,
                        expectedEntryID: entryID,
                        visibleEntryID: self.results.indices.contains(row)
                            ? self.results[row].entry.id
                            : nil
                      ) else { return }
                self.previewIcon.image = image.value
                self.previewThumbnailRequest = nil
            }
        }
    }

    private func cancelPreviewThumbnailRequest() {
        guard let request = previewThumbnailRequest else { return }
        QLThumbnailGenerator.shared.cancel(request)
        previewThumbnailRequest = nil
    }

    nonisolated private static func filePreviewDetails(path: String, isDirectory: Bool) -> String {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .localizedTypeDescriptionKey,
        ])
        var components: [String] = []
        components.append(values?.localizedTypeDescription ?? (isDirectory ? "Folder" : "File"))
        if !isDirectory, let size = values?.fileSize {
            components.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let modified = values?.contentModificationDate {
            components.append("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
        }
        components.append(url.deletingLastPathComponent().path)
        return components.joined(separator: "\n")
    }
}
