@preconcurrency import AppKit
import BroccoliCore
import Foundation
import SwiftUI

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
    /// Command-number shortcuts use the digit keys. Visible Results can be 10, but there is
    /// no tenth digit, so the badges and the key equivalents both stop at 9.
    static let maximum = 9

    static func limit(visibleResultCount: Int) -> Int {
        min(maximum, max(0, visibleResultCount))
    }

    static func row(for characters: String, visibleResultCount: Int) -> Int? {
        guard let number = Int(characters),
              (1...limit(visibleResultCount: visibleResultCount)).contains(number) else { return nil }
        return number - 1
    }

    static func label(forRow row: Int, visibleResultCount: Int) -> String? {
        guard (0..<limit(visibleResultCount: visibleResultCount)).contains(row) else { return nil }
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
        let maximumSteps = 1
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

/// Holding an arrow walks the list. The gap is only wide enough to stop the fastest
/// system repeat from skipping rows; a normal hold keeps the user's key-repeat pace.
struct LauncherArrowRepeatGate {
    private(set) var lastMove: ContinuousClock.Instant?
    var interval: Duration = .milliseconds(40)

    mutating func allow(isRepeat: Bool, now: ContinuousClock.Instant = .now) -> Bool {
        if !isRepeat {
            lastMove = now
            return true
        }
        if let lastMove, lastMove.duration(to: now) < interval {
            return false
        }
        lastMove = now
        return true
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
        originX: CGFloat,
        originY: CGFloat
    ) -> NSRect {
        let width = min(preferredWidth, max(0, visibleFrame.width - 80))
        let height = max(0, height)
        let availableWidth = max(0, visibleFrame.width - width)
        let x = visibleFrame.minX + originX * availableWidth
        let topInset = originY * visibleFrame.height
        let frame = NSRect(
            x: x,
            y: visibleFrame.maxY - height - topInset,
            width: width,
            height: height
        )
        return clamped(frame, to: visibleFrame)
    }

    /// Keeps the panel inside `visibleFrame` without changing its size. A panel taller than
    /// the visible frame stays top-aligned so the search field remains reachable.
    static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var frame = frame
        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY, frame.height <= visibleFrame.height {
            frame.origin.y = visibleFrame.minY
        }
        return frame
    }

    /// Remaining-width `x` (0 = leading, 0.5 = centered) and top-inset fraction `y`.
    static func normalizedOrigin(for frame: NSRect, in visibleFrame: NSRect) -> (x: CGFloat, y: CGFloat) {
        let availableWidth = visibleFrame.width - frame.width
        let x: CGFloat
        if availableWidth > 0 {
            x = (frame.minX - visibleFrame.minX) / availableWidth
        } else {
            x = CGFloat(LauncherAppearancePreferences.defaultOriginX)
        }
        let y = visibleFrame.height > 0
            ? (visibleFrame.maxY - frame.maxY) / visibleFrame.height
            : CGFloat(LauncherAppearancePreferences.defaultOriginY)
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    static func committedPlacement(
        frame: NSRect,
        visibleFrame: NSRect
    ) -> (frame: NSRect, originX: CGFloat, originY: CGFloat) {
        let frame = clamped(frame, to: visibleFrame)
        let origin = normalizedOrigin(for: frame, in: visibleFrame)
        return (frame, origin.x, origin.y)
    }

    /// Search typing and result-row clicks must keep their own mouse tracking.
    @MainActor
    static func isDraggableChrome(
        hitView: NSView?,
        searchField: NSView,
        resultsView: NSView
    ) -> Bool {
        guard let hitView else { return true }
        if hitView === searchField || hitView.isDescendant(of: searchField) { return false }
        if hitView === resultsView || hitView.isDescendant(of: resultsView) { return false }
        return true
    }
}

private final class LauncherSearchField: NSTextField {
    var onCommand: ((SearchFieldCommand) -> Void)?
    var numericShortcutLimit = LauncherNumericShortcut.maximum
    private var arrowRepeatGate = LauncherArrowRepeatGate()

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
           let row = LauncherNumericShortcut.row(
               for: characters,
               visibleResultCount: numericShortcutLimit
           ) {
            onCommand?(.executeIndex(row))
            return
        }
        switch event.keyCode {
        case 125, 126:
            guard arrowRepeatGate.allow(isRepeat: event.isARepeat) else { return }
            onCommand?(event.keyCode == 125 ? .down : .up)
        case 36, 76: onCommand?(.execute)
        case 53: onCommand?(.dismiss)
        default: super.keyDown(with: event)
        }
    }
}

/// Every launcher design uses one native AppKit search field so its magnifier, query,
/// placeholder, clear button, and accessibility semantics cannot drift between themes.
/// The metrics scale as one optical unit: changing a theme's query size also changes the
/// symbol canvas and cancel control while retaining the same compact icon-to-text rhythm.
@MainActor
struct LauncherSearchMetrics: Equatable {
    static let sharedEmptyInsertionPointLeadingGap: CGFloat = 1.5
    static let spotlight = LauncherSearchMetrics(fontSize: 26)
    static let figmaLiquidGlass = LauncherSearchMetrics(
        fontSize: LauncherLiquidGlassMetrics.searchFontSize,
        symbolSize: LauncherLiquidGlassMetrics.searchSymbolSize,
        symbolPointSize: LauncherLiquidGlassMetrics.searchSymbolPointSize,
        symbolTextGap: LauncherLiquidGlassMetrics.searchSymbolTextGap,
        textLeadingCompensation: LauncherLiquidGlassMetrics.searchTextHorizontalOffset,
        fieldEditorTextLeadingCorrection:
            LauncherLiquidGlassMetrics.fieldEditorTextLeadingCorrection,
        symbolDrawingScale: LauncherLiquidGlassMetrics.searchSymbolDrawingScale,
        symbolDrawingVerticalScale: LauncherLiquidGlassMetrics.searchSymbolDrawingVerticalScale
    )
    static let figmaMinimal = LauncherSearchMetrics(
        fontSize: LauncherMinimalMetrics.searchFontSize,
        symbolSize: LauncherMinimalMetrics.searchSymbolSize,
        symbolPointSize: LauncherMinimalMetrics.searchSymbolPointSize,
        symbolTextGap: LauncherMinimalMetrics.searchSymbolTextGap,
        textLeadingCompensation: LauncherMinimalMetrics.nativeTextLeadingCompensation,
        symbolDrawingScale: LauncherMinimalMetrics.searchSymbolDrawingScale,
        symbolDrawingVerticalScale: LauncherMinimalMetrics.searchSymbolDrawingVerticalScale
    )

    let fontSize: CGFloat
    let symbolSize: CGFloat
    let symbolPointSize: CGFloat
    let symbolTextGap: CGFloat
    let textLeadingCompensation: CGFloat
    let fieldEditorTextLeadingCorrection: CGFloat
    let emptyInsertionPointLeadingGap: CGFloat
    let symbolDrawingScale: CGFloat
    let symbolDrawingVerticalScale: CGFloat

    init(
        fontSize: CGFloat,
        symbolSize: CGFloat? = nil,
        symbolPointSize: CGFloat? = nil,
        symbolTextGap: CGFloat = 10,
        textLeadingCompensation: CGFloat = 0,
        fieldEditorTextLeadingCorrection: CGFloat = 0,
        symbolDrawingScale: CGFloat = 1,
        symbolDrawingVerticalScale: CGFloat = 1
    ) {
        self.fontSize = fontSize
        self.symbolSize = symbolSize ?? fontSize + 8
        self.symbolPointSize = symbolPointSize ?? (symbolSize ?? fontSize + 8) - 2
        self.symbolTextGap = symbolTextGap
        self.textLeadingCompensation = textLeadingCompensation
        self.fieldEditorTextLeadingCorrection = fieldEditorTextLeadingCorrection
        self.emptyInsertionPointLeadingGap = Self.sharedEmptyInsertionPointLeadingGap
        self.symbolDrawingScale = symbolDrawingScale
        self.symbolDrawingVerticalScale = symbolDrawingVerticalScale
    }

    var cancelSize: CGFloat { min(20, max(16, fontSize * 0.7)) }
    var cancelTrailingInset: CGFloat { 2 }
    var font: NSFont { .systemFont(ofSize: fontSize, weight: .regular) }
}

/// Composites a view's ink by adding it to what is beneath it, as SwiftUI's `.plusLighter`
/// does, so opaque neutral gray ink takes its hue from the surface instead of imposing one.
@MainActor
enum LauncherAdditiveInk {
    /// The Core Animation plus-lighter compositing filter; Core Image's addition filter
    /// composites in linear light and does not match SwiftUI's blend.
    static let filterName = "plusL"

    static func apply(_ enabled: Bool, to view: NSView) {
        if enabled {
            view.wantsLayer = true
            view.layer?.compositingFilter = filterName
        } else if view.layer?.compositingFilter != nil {
            view.layer?.compositingFilter = nil
        }
    }

    static func isApplied(to view: NSView) -> Bool {
        (view.layer?.compositingFilter as? String) == filterName
    }
}

/// Draws the shared horizontal header rule as actual one-point ink, without rotating or
/// resampling a layer and softening the endpoints on Retina.
@MainActor
final class LauncherHeaderSeparatorView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    var lineThickness: CGFloat = 1 { didSet { needsDisplay = true } }
    var angleDegrees: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0, color.alphaComponent > 0 else { return }
        let halfLine = lineThickness / 2
        let rise = abs(tan(angleDegrees * .pi / 180) * bounds.width)
        let leftY = min(bounds.height - halfLine, halfLine + rise)
        let rightY = halfLine
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: leftY))
        path.line(to: NSPoint(x: bounds.width, y: rightY))
        path.lineWidth = lineThickness
        color.setStroke()
        path.stroke()
    }
}

@MainActor
struct LauncherSearchGeometry {
    /// Spotlight gives the search glyph nearly the same optical height as its query text.
    /// SF Symbols include transparent side bearings. A 34-point drawing box produces a
    /// roughly 29-point visible magnifier, matching Spotlight's optical scale beside 26-point
    /// type. A 10-point box gap resolves to approximately 15 visible points, eliminating
    /// the detached icon-to-query spacing visible in the previous build.
    static let symbolSize = LauncherSearchMetrics.spotlight.symbolSize
    static let symbolPointSize = LauncherSearchMetrics.spotlight.symbolPointSize
    static let symbolTextGap = LauncherSearchMetrics.spotlight.symbolTextGap
    static let cancelSize = LauncherSearchMetrics.spotlight.cancelSize
    static let cancelTrailingInset = LauncherSearchMetrics.spotlight.cancelTrailingInset
    static let font = LauncherSearchMetrics.spotlight.font

    /// Space between the scope token and the magnifier that follows it.
    static let leadingAccessoryTextGap: CGFloat = 10

    let bounds: NSRect
    var metrics: LauncherSearchMetrics = .spotlight
    /// Width of a scope token (Files, Clipboard) drawn ahead of the magnifier.
    var leadingAccessoryWidth: CGFloat = 0

    /// The token keeps the field's leading edge. The magnifier, query, placeholder, caret,
    /// and inline suggestion all start after it.
    func leadingAccessoryRect(height: CGFloat) -> NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.midY - height / 2,
            width: leadingAccessoryWidth,
            height: height
        )
    }

    var searchButtonRect: NSRect {
        let originX = bounds.minX + (
            leadingAccessoryWidth > 0 ? leadingAccessoryWidth + Self.leadingAccessoryTextGap : 0
        )
        return NSRect(
            x: originX,
            y: bounds.midY - metrics.symbolSize / 2,
            width: metrics.symbolSize,
            height: metrics.symbolSize
        )
    }

    var cancelButtonRect: NSRect {
        NSRect(
            x: bounds.maxX - metrics.cancelTrailingInset - metrics.cancelSize,
            y: bounds.midY - metrics.cancelSize / 2,
            width: metrics.cancelSize,
            height: metrics.cancelSize
        )
    }

    var searchTextRect: NSRect {
        let leading = searchButtonRect.maxX
            + metrics.symbolTextGap
            + metrics.textLeadingCompensation
        let trailing = cancelButtonRect.minX - 10
        let lineHeight = ceil(metrics.font.ascender - metrics.font.descender + metrics.font.leading)
        let textRectHeight = min(bounds.height, lineHeight)
        return NSRect(
            x: leading,
            y: bounds.midY - textRectHeight / 2,
            width: max(0, trailing - leading),
            height: textRectHeight
        )
    }
}

final class LauncherNativeSearchFieldCell: NSSearchFieldCell {
    var searchMetrics: LauncherSearchMetrics = .spotlight
    var leadingAccessoryWidth: CGFloat = 0

    func geometry(forBounds rect: NSRect) -> LauncherSearchGeometry {
        LauncherSearchGeometry(
            bounds: rect,
            metrics: searchMetrics,
            leadingAccessoryWidth: leadingAccessoryWidth
        )
    }

    func editorRect(forBounds rect: NSRect, isEmpty: Bool) -> NSRect {
        let textRect = searchTextRect(forBounds: rect)
        let leadingAllowance = isEmpty
            ? searchMetrics.emptyInsertionPointLeadingGap
            : searchMetrics.fieldEditorTextLeadingCorrection
        return NSRect(
            x: textRect.minX - leadingAllowance,
            y: textRect.minY,
            width: textRect.width + leadingAllowance,
            height: textRect.height
        )
    }

    func configureFieldEditor(_ text: NSText, isEmpty: Bool) {
        guard let editor = text as? NSTextView else { return }
        // AppKit restores the shared field editor's default five-point fragment padding when
        // the results panel collapses after the final backspace. Reapply the search geometry
        // after every native edit/select pass so the caret cannot move into the placeholder.
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(
            width: isEmpty ? searchMetrics.emptyInsertionPointLeadingGap : 0,
            height: 0
        )
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        geometry(forBounds: rect).searchButtonRect
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        geometry(forBounds: rect).searchTextRect
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        geometry(forBounds: rect).cancelButtonRect
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
        let isEmpty = textObj.string.isEmpty
        super.edit(
            withFrame: editorRect(forBounds: aRect, isEmpty: isEmpty),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
        configureFieldEditor(textObj, isEmpty: isEmpty)
    }

    override func select(
        withFrame aRect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        let isEmpty = textObj.string.isEmpty
        super.select(
            withFrame: editorRect(forBounds: aRect, isEmpty: isEmpty),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
        configureFieldEditor(textObj, isEmpty: isEmpty)
    }
}

private final class LauncherSearchPlaceholderView: NSTextView {
    var attributedString: NSAttributedString {
        get { textStorage?.copy() as? NSAttributedString ?? NSAttributedString() }
        set { applyAttributedString(newValue) }
    }

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: frameRect.size)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: frameRect, textContainer: container)
        configurePlaceholderLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePlaceholderLayout()
    }

    private func configurePlaceholderLayout() {
        drawsBackground = false
        isEditable = false
        isSelectable = false
        isRichText = false
        importsGraphics = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        usesAdaptiveColorMappingForDarkAppearance = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = true
    }

    /// `isRichText = false` paints `textColor`, not attributed foreground. The magnifier is
    /// already a baked device-ink bitmap; this view must use that same color as its only ink.
    private func applyAttributedString(_ string: NSAttributedString) {
        textStorage?.setAttributedString(string)
        guard string.length > 0 else {
            textColor = .clear
            return
        }
        if let font = string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            self.font = font
        }
        if let color = string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
            textColor = color
            typingAttributes[.foregroundColor] = color
        }
        needsDisplay = true
    }

    override var allowsVibrancy: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The Files and Clipboard scope shown ahead of the magnifier. The label keeps its
/// intrinsic size and Auto Layout centers it, so the title is optically centered in the
/// pill at any font metrics; the pill's width follows the title.
final class LauncherSearchScopeTokenView: NSView {
    static let height: CGFloat = 26
    static let horizontalPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 8

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.setAccessibilityElement(false)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    var title: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var titleFrame: NSRect { label.alignmentRect(forFrame: label.frame) }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: ceil(label.intrinsicContentSize.width) + Self.horizontalPadding * 2,
            height: Self.height
        )
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class LauncherNativeSearchField: NSSearchField {
    private let centeredPlaceholderView = LauncherSearchPlaceholderView(frame: .zero)
    private let inlineSuggestionView = LauncherSearchPlaceholderView(frame: .zero)
    private let scopeTokenView = LauncherSearchScopeTokenView(frame: .zero)
    private(set) var centeredPlaceholderAttributedString: NSAttributedString?
    private(set) var inlineSuggestionText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCenteredPlaceholderView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCenteredPlaceholderView()
    }

    override var stringValue: String {
        didSet {
            updateCenteredPlaceholderVisibility()
            needsLayout = true
        }
    }

    var searchMetrics: LauncherSearchMetrics = .spotlight {
        didSet {
            (cell as? LauncherNativeSearchFieldCell)?.searchMetrics = searchMetrics
            font = searchMetrics.font
            needsLayout = true
            needsDisplay = true
        }
    }

    /// The native placeholder changes baseline when AppKit installs its field editor. Store the
    /// launcher placeholder separately so the cell can draw it at one focus-independent center.
    func setCenteredPlaceholder(_ placeholder: NSAttributedString?) {
        centeredPlaceholderAttributedString = placeholder?.copy() as? NSAttributedString
        if let placeholder = centeredPlaceholderAttributedString {
            // NSSearchField can retain and redraw its last native placeholder after the shared
            // field editor is installed. Keep that native layout value, but make its ink clear;
            // the focus-independent child view below is the only visible placeholder.
            let nativePlaceholder = NSMutableAttributedString(attributedString: placeholder)
            nativePlaceholder.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: NSRange(location: 0, length: nativePlaceholder.length)
            )
            placeholderAttributedString = nativePlaceholder
        } else {
            placeholderAttributedString = nil
            placeholderString = nil
        }
        centeredPlaceholderView.attributedString =
            centeredPlaceholderAttributedString ?? NSAttributedString()
        updateCenteredPlaceholderVisibility()
        needsLayout = true
    }

    private func configureCenteredPlaceholderView() {
        addSubview(centeredPlaceholderView, positioned: .above, relativeTo: nil)
        inlineSuggestionView.isHidden = true
        inlineSuggestionView.setAccessibilityRole(.staticText)
        addSubview(inlineSuggestionView, positioned: .above, relativeTo: centeredPlaceholderView)
        scopeTokenView.isHidden = true
        addSubview(scopeTokenView, positioned: .above, relativeTo: inlineSuggestionView)
    }

    /// Shows a scope token such as “Files” ahead of the magnifier, or removes it.
    /// The cell reserves the token's width, so the magnifier, text, caret, placeholder, and
    /// inline suggestion move together from the shared search geometry.
    func setScope(_ title: String?) {
        scopeTokenView.title = title ?? ""
        scopeTokenView.isHidden = title == nil
        (cell as? LauncherNativeSearchFieldCell)?.leadingAccessoryWidth = searchGeometry.leadingAccessoryWidth
        needsLayout = true
        needsDisplay = true
    }

    func setInlineSuggestion(
        _ text: String?,
        color: NSColor,
        accessibilityLabel: String? = nil
    ) {
        inlineSuggestionText = text
        inlineSuggestionView.attributedString = NSAttributedString(
            string: text ?? "",
            attributes: [
                .font: searchMetrics.font,
                .foregroundColor: color,
            ]
        )
        inlineSuggestionView.setAccessibilityLabel(accessibilityLabel)
        inlineSuggestionView.isHidden = text == nil
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func updateCenteredPlaceholderVisibility() {
        centeredPlaceholderView.isHidden = !stringValue.isEmpty
            || centeredPlaceholderAttributedString == nil
    }

    override func layout() {
        super.layout()
        // Placeholder and live query now use the same TextKit layout engine. Keeping their
        // outer rectangles identical removes the baseline difference between direct string
        // drawing and NSTextView rendering.
        centeredPlaceholderView.frame = searchTextBounds
        if !scopeTokenView.isHidden {
            scopeTokenView.frame = backingAlignedRect(
                searchGeometry.leadingAccessoryRect(height: LauncherSearchScopeTokenView.height),
                options: .alignAllEdgesNearest
            )
        }
        layoutInlineSuggestion()
    }

    private func layoutInlineSuggestion() {
        guard let inlineSuggestionText, !inlineSuggestionText.isEmpty else {
            inlineSuggestionView.frame = .zero
            inlineSuggestionView.isHidden = true
            return
        }

        let textBounds = searchTextBounds
        let queryEndX = queryEndX(in: textBounds)
        let originX = ceil(queryEndX + 8)
        let availableWidth = floor(textBounds.maxX - originX)
        guard availableWidth >= 24 else {
            inlineSuggestionView.frame = .zero
            inlineSuggestionView.isHidden = true
            return
        }

        let suggestionSize = (inlineSuggestionText as NSString).size(
            withAttributes: [.font: searchMetrics.font]
        )
        let height = min(textBounds.height, ceil(suggestionSize.height))
        inlineSuggestionView.frame = backingAlignedRect(
            NSRect(
                x: originX,
                y: textBounds.midY - height / 2,
                width: min(ceil(suggestionSize.width) + 2, availableWidth),
                height: height
            ),
            options: .alignAllEdgesNearest
        )
        inlineSuggestionView.isHidden = false
    }

    private func queryEndX(in textBounds: NSRect) -> CGFloat {
        if let editor = currentEditor() as? NSTextView,
           let window = editor.window {
            if let textContainer = editor.textContainer {
                editor.layoutManager?.ensureLayout(for: textContainer)
            }
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let endRange = NSRange(location: editor.string.utf16.count, length: 0)
            let screenRect = editor.firstRect(
                forCharacterRange: endRange,
                actualRange: &actualRange
            )
            if screenRect.height > 0 {
                let windowRect = window.convertFromScreen(screenRect)
                return convert(windowRect, from: nil).maxX
            }
        }

        let queryWidth = ceil((stringValue as NSString).size(
            withAttributes: [.font: searchMetrics.font]
        ).width)
        return min(textBounds.maxX, textBounds.minX + queryWidth)
    }

    var inlineSuggestionFrame: NSRect? {
        inlineSuggestionView.isHidden ? nil : inlineSuggestionView.frame
    }

    private var searchGeometry: LauncherSearchGeometry {
        LauncherSearchGeometry(
            bounds: bounds,
            metrics: searchMetrics,
            leadingAccessoryWidth: scopeTokenView.isHidden ? 0 : scopeTokenView.intrinsicContentSize.width
        )
    }

    override var searchButtonBounds: NSRect {
        backingAlignedRect(searchGeometry.searchButtonRect, options: .alignAllEdgesNearest)
    }

    override var searchTextBounds: NSRect {
        backingAlignedRect(searchGeometry.searchTextRect, options: .alignAllEdgesNearest)
    }

    override var cancelButtonBounds: NSRect {
        backingAlignedRect(searchGeometry.cancelButtonRect, options: .alignAllEdgesNearest)
    }

    var scopeTokenFrame: NSRect? {
        scopeTokenView.isHidden ? nil : scopeTokenView.frame
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        updateCenteredPlaceholderVisibility()
        configureCurrentFieldEditor()
        // A transparent field editor can otherwise leave a one-frame trace of the previous
        // query while AppKit resizes the result panel. Repaint the complete text stack after
        // every replacement or deletion instead of relying on the editor's narrow dirty rect.
        needsDisplay = true
        currentEditor()?.needsDisplay = true
        currentEditor()?.superview?.needsDisplay = true
        needsLayout = true
    }

    /// Configure AppKit's shared editor without taking ownership of its frame. NSSearchFieldCell
    /// already installs the clip view in `editorRect`; rewriting both the clip and document
    /// frames here made AppKit's normal click-to-selection layout fight our layout pass.
    func configureCurrentFieldEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        (cell as? LauncherNativeSearchFieldCell)?.configureFieldEditor(
            editor,
            isEmpty: editor.string.isEmpty
        )
        needsLayout = true
    }
}

@MainActor
enum LauncherNativeSearchFieldStyle {
    static func placeholder(
        _ string: String,
        metrics: LauncherSearchMetrics,
        color: NSColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: metrics.font,
                .foregroundColor: color,
            ]
        )
    }

    /// Preserve the optical canvas while baking device ink. Hierarchical symbols such as
    /// `xmark.circle.fill` keep their knockout only when drawn as a template; a single
    /// palette color fills the X and the cancel control reads as a solid disc.
    private static func nativeSymbol(
        named name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        size: CGFloat,
        drawingScale: CGFloat = 1,
        drawingVerticalScale: CGFloat = 1,
        tint: NSColor? = nil
    ) -> NSImage? {
        guard let base = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        ) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = base.withSymbolConfiguration(configuration) else { return nil }
        symbol.isTemplate = true
        let outputSize = NSSize(width: size, height: size)
        let image = NSImage(size: outputSize, flipped: false) { rect in
            // Never let an optical scale request extend the SF Symbol beyond its button canvas.
            // AppKit clips that overflow, most visibly at the magnifier handle.
            let drawingSize = NSSize(
                width: min(rect.width, rect.width * drawingScale),
                height: min(rect.height, rect.height * drawingVerticalScale)
            )
            let drawingRect = NSRect(
                x: rect.midX - drawingSize.width / 2,
                y: rect.midY - drawingSize.height / 2,
                width: drawingSize.width,
                height: drawingSize.height
            )
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            symbol.draw(
                in: drawingRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            if let tint {
                context.saveGState()
                context.setBlendMode(.sourceIn)
                tint.setFill()
                context.fill(rect)
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = tint == nil
        image.alignmentRect = NSRect(origin: .zero, size: outputSize)
        return image
    }

    static func apply(to searchField: NSSearchField, fontSize: CGFloat = 26) {
        apply(
            to: searchField,
            metrics: LauncherSearchMetrics(fontSize: fontSize),
            iconColor: .labelColor
        )
    }

    static func apply(
        to searchField: NSSearchField,
        metrics: LauncherSearchMetrics,
        iconColor: NSColor,
        placeholderColor: NSColor? = nil
    ) {
        let cell = (searchField.cell as? LauncherNativeSearchFieldCell) ?? LauncherNativeSearchFieldCell(textCell: "")
        cell.searchMetrics = metrics
        if searchField.cell !== cell { searchField.cell = cell }
        (searchField as? LauncherNativeSearchField)?.searchMetrics = metrics
        let defaultPlaceholder = placeholder(
            "Search",
            metrics: metrics,
            color: placeholderColor ?? iconColor
        )
        if let searchField = searchField as? LauncherNativeSearchField {
            searchField.setCenteredPlaceholder(defaultPlaceholder)
        } else {
            searchField.placeholderAttributedString = defaultPlaceholder
        }
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.controlSize = .large
        searchField.font = metrics.font
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        if let magnifier = nativeSymbol(
            named: "magnifyingglass",
            pointSize: metrics.symbolPointSize,
            weight: .regular,
            size: metrics.symbolSize,
            drawingScale: metrics.symbolDrawingScale,
            drawingVerticalScale: metrics.symbolDrawingVerticalScale,
            tint: iconColor
        ) {
            cell.searchButtonCell?.image = magnifier
            cell.searchButtonCell?.imageScaling = .scaleProportionallyUpOrDown
            cell.searchButtonCell?.imageDimsWhenDisabled = false
            cell.searchButtonCell?.highlightsBy = []
            cell.searchButtonCell?.showsStateBy = []
        }
        if let cancel = nativeSymbol(
            named: "xmark.circle.fill",
            pointSize: 15,
            weight: .regular,
            size: metrics.cancelSize,
            tint: iconColor
        ) {
            cell.cancelButtonCell?.image = cancel
            cell.cancelButtonCell?.imageScaling = .scaleProportionallyUpOrDown
            cell.cancelButtonCell?.imageDimsWhenDisabled = false
            cell.cancelButtonCell?.highlightsBy = []
            cell.cancelButtonCell?.showsStateBy = []
        }
        searchField.cell?.lineBreakMode = .byTruncatingTail
        searchField.setAccessibilityRole(.textField)
        searchField.setAccessibilitySubrole(.searchField)
    }
}

/// Dark Liquid Glass backdrop. The material is darkened only by neutral black, so all of the
/// surface's color comes from the desktop. It fills its bounds; the surface's glass clip
/// gives it the rounded outline.
struct LauncherDarkGlassBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.clear).background(LauncherLiquidGlassMetrics.darkMaterial)
            Rectangle().fill(Color.black.opacity(LauncherLiquidGlassMetrics.darkShadeOpacity))
        }
        .transaction { $0.disablesAnimations = true }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

private final class LauncherDarkGlassBackdropView: NSHostingView<LauncherDarkGlassBackdrop> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The complete Liquid Glass launcher surface.
///
/// Light is one continuous behind-window HUD material. Dark is SwiftUI's regular material
/// darkened with neutral black: every AppKit material blends the backdrop toward gray, which
/// reads as a dusty veil over saturated wallpaper, while the SwiftUI backdrop keeps its hue.
/// `NSGlassEffectView` was measured against both: at pill size its lens contributes almost no
/// blur, and it samples in-window content, so nothing may be layered beneath it.
///
/// Do not layer-back the HUD itself to round it. A layer-backed visual-effect view drops
/// vibrancy, so Light labels and the header rule would composite as plain gray over wallpaper.
/// The glass clip is an ancestor that rounds the HUD, the Dark backdrop, and the content
/// together. Dark content cannot live inside the effect view at all (it would sit over the
/// HUD), so the content moves onto the SwiftUI backdrop and its ink composites additively.
///
/// The glass clip is the only layer that antialiases the outline, and the Dark rim is drawn
/// once above it with the same geometry. A rim stroked inside that outline and then clipped
/// by it again loses part of its outer pixels along the arcs but not along the straight
/// edges, so it thins abruptly where each arc begins.
@MainActor
final class LauncherLiquidGlassSurfaceView: NSView {
    static let cornerRadius = LauncherLiquidGlassMetrics.cornerRadius
    static let cornerCurve = LauncherLiquidGlassMetrics.cornerCurve
    static let collapsedHeight = LauncherLiquidGlassMetrics.searchHeight

    let glassClip = NSView()
    let rim = LauncherGlassRimView()
    private let materialView = NSVisualEffectView()
    private let darkBackdrop = LauncherDarkGlassBackdropView(rootView: LauncherDarkGlassBackdrop())
    private var hostedContent: NSView?
    private(set) var usesDarkBackdrop = false

    init(frame frameRect: NSRect = .zero, interactive: Bool = false) {
        super.init(frame: frameRect)
        // Keep this argument source-compatible with live and preview callers. The surface is
        // passive in both: it must never paint a local response lens around editable content.
        _ = interactive

        // Configure the persistent surface once. Resizing must not select a different
        // material, blending mode, or corner treatment. AppKit handles Reduce Transparency and
        // Increase Contrast for the HUD, and SwiftUI does for the Dark material.
        glassClip.frame = bounds
        glassClip.autoresizingMask = [.width, .height]
        glassClip.wantsLayer = true
        glassClip.layer?.cornerRadius = Self.cornerRadius
        glassClip.layer?.cornerCurve = Self.cornerCurve
        glassClip.layer?.masksToBounds = true
        addSubview(glassClip)
        darkBackdrop.sizingOptions = []
        darkBackdrop.frame = bounds
        darkBackdrop.autoresizingMask = [.width, .height]
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        glassClip.addSubview(materialView)
        rim.frame = bounds
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
        updateSurfaceForAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glassClip.frame = bounds
        materialView.frame = glassClip.bounds
        darkBackdrop.frame = glassClip.bounds
        rim.frame = bounds
        // Detached previews can resolve a new appearance without delivering the change
        // callback before capture.
        updateSurfaceForAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceForAppearance()
    }

    private func updateSurfaceForAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        rim.update(
            visible: isDark,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        let darkInstalled = darkBackdrop.superview != nil
        guard isDark != usesDarkBackdrop || darkInstalled != isDark else { return }
        usesDarkBackdrop = isDark
        // Move content before hiding the HUD. Hiding an ancestor of the first responder
        // makes the window take first responder and ends the edit. The HUD stays in the
        // window: removing it does the same. An inactive effect does not sample, so it
        // cannot draw a second background under the SwiftUI material or resample on
        // every height step.
        if let hostedContent { attach(hostedContent) }
        if darkBackdrop.superview == nil {
            glassClip.addSubview(darkBackdrop, positioned: .below, relativeTo: hostedContent)
        }
        darkBackdrop.isHidden = !isDark
        materialView.isHidden = isDark
        materialView.state = isDark ? .inactive : .active
    }

    func setContentView(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        // Give content destination geometry before activating constraints: a detached
        // preview has no window display cycle to expand a zero-sized effect view afterward,
        // so it would otherwise settle at the search field's fitting height.
        glassClip.frame = bounds
        materialView.frame = bounds
        darkBackdrop.frame = bounds
        view.frame = bounds
        view.translatesAutoresizingMaskIntoConstraints = false
        attach(view)
    }

    /// Light content sits on the HUD so labels stay in its vibrancy hierarchy; Dark content
    /// sits above the SwiftUI backdrop. Moving between visible parents keeps the field editor,
    /// its selection, and marked text.
    private func attach(_ view: NSView) {
        let parent: NSView = usesDarkBackdrop ? glassClip : materialView
        guard view.superview !== parent else { return }
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

/// The Dark one-point rim: neutral gray added to the surface beneath it with plus-lighter.
/// A layer border shares its corner geometry with the glass clip's mask exactly.
@MainActor
final class LauncherGlassRimView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = LauncherLiquidGlassMetrics.cornerRadius
        layer?.cornerCurve = LauncherLiquidGlassMetrics.cornerCurve
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        LauncherAdditiveInk.apply(true, to: self)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(visible: Bool, increasedContrast: Bool) {
        isHidden = !visible
        let lift = CGFloat(increasedContrast
            ? LauncherLiquidGlassMetrics.darkRimLiftIncreasedContrast
            : LauncherLiquidGlassMetrics.darkRimLift)
        let color = NSColor(srgbRed: lift, green: lift, blue: lift, alpha: 1).cgColor
        if layer?.borderColor != color { layer?.borderColor = color }
    }
}

private final class LauncherPanel: NSPanel {
    var onCommand: ((SearchFieldCommand) -> Void)?
    var numericShortcutLimit = LauncherNumericShortcut.maximum
    /// Return `true` to consume the mouse-down and hand the move to Window Server.
    var onPotentialMove: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Geometry already clamps live presentation to the visible frame. Returning the
        // requested rect unchanged lets automated tests keep the panel off-screen; AppKit
        // would otherwise snap `(0, 0)` and negative origins to the bottom-left of the desktop.
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, onPotentialMove?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            onCommand?(.preferences)
            return true
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let row = LauncherNumericShortcut.row(
               for: characters,
               visibleResultCount: numericShortcutLimit
           ) {
            onCommand?(.executeIndex(row))
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Trackpad and mouse-wheel scrolling walks the selection the same way the arrow keys do.
/// The highlight stays inside the visible rows. Once it is on the first or last visible row,
/// another step scrolls the list so the next match takes that same slot.
private final class LauncherResultsScrollView: NSScrollView {
    var onSelectionStep: ((Bool) -> Void)?
    private var accumulator = LauncherScrollAccumulator()

    override func scrollWheel(with event: NSEvent) {
        // Momentum after the fingers lift is the system fling. Walking the highlight
        // through that fling is what made one flick race down the list.
        guard event.momentumPhase == [] else { return }
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
    static let statusIconSize = LauncherLiquidGlassMetrics.statusIconSize

    private let iconSlot = NSLayoutGuide()
    private let resultIcon = ResultIconView()
    private let settingsBadge = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let textGroupGuide = NSLayoutGuide()
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconDrawingWidthConstraint: NSLayoutConstraint!
    private var iconDrawingHeightConstraint: NSLayoutConstraint!
    private var settingsBadgeSizeConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var titleTopConstraint: NSLayoutConstraint!
    private var subtitleTopConstraint: NSLayoutConstraint!
    private var subtitleBottomConstraint: NSLayoutConstraint!
    private var textGroupCenterConstraint: NSLayoutConstraint!
    private var titleCenterConstraint: NSLayoutConstraint!
    private var titleToShortcutConstraint: NSLayoutConstraint!
    private var subtitleToShortcutConstraint: NSLayoutConstraint!
    private var titleToEdgeConstraint: NSLayoutConstraint!
    private var subtitleToEdgeConstraint: NSLayoutConstraint!
    private var selected = false
    private var selectionColor = NSColor.controlAccentColor
    private var selectedTextColor = NSColor.alternateSelectedControlTextColor
    private var selectedShortcutTextColor = NSColor.alternateSelectedControlTextColor
    private var usesFullWidthSelectionBackground = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelectionBackground()
        updateColors()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateSelectionBackground()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        resultIcon.translatesAutoresizingMaskIntoConstraints = false
        resultIcon.imageScaling = .scaleProportionallyUpOrDown
        resultIcon.imageAlignment = .alignCenter
        settingsBadge.translatesAutoresizingMaskIntoConstraints = false
        settingsBadge.imageScaling = .scaleProportionallyUpOrDown
        settingsBadge.isHidden = true
        settingsBadge.setAccessibilityElement(false)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        shortcutLabel.alignment = .right
        addLayoutGuide(iconSlot)
        addSubview(resultIcon)
        addSubview(settingsBadge, positioned: .above, relativeTo: resultIcon)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(shortcutLabel)
        addLayoutGuide(textGroupGuide)
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: textGroupGuide.topAnchor)
        subtitleTopConstraint = subtitleLabel.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor
        )
        subtitleBottomConstraint = subtitleLabel.bottomAnchor.constraint(
            equalTo: textGroupGuide.bottomAnchor
        )
        textGroupCenterConstraint = textGroupGuide.centerYAnchor.constraint(
            equalTo: centerYAnchor
        )
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
        iconLeadingConstraint = iconSlot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        iconWidthConstraint = iconSlot.widthAnchor.constraint(equalToConstant: 40)
        iconHeightConstraint = iconSlot.heightAnchor.constraint(equalToConstant: 40)
        iconDrawingWidthConstraint = resultIcon.widthAnchor.constraint(equalToConstant: 40)
        iconDrawingHeightConstraint = resultIcon.heightAnchor.constraint(equalToConstant: 40)
        settingsBadgeSizeConstraint = settingsBadge.widthAnchor.constraint(
            equalToConstant: LauncherLiquidGlassMetrics.resultSettingsBadgeSize
        )
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: iconSlot.trailingAnchor,
            constant: 4
        )
        NSLayoutConstraint.activate([
            iconLeadingConstraint,
            iconSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,
            resultIcon.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            resultIcon.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            iconDrawingWidthConstraint,
            iconDrawingHeightConstraint,
            settingsBadge.trailingAnchor.constraint(equalTo: resultIcon.trailingAnchor),
            settingsBadge.bottomAnchor.constraint(equalTo: resultIcon.bottomAnchor),
            settingsBadgeSizeConstraint,
            settingsBadge.heightAnchor.constraint(equalTo: settingsBadge.widthAnchor),
            titleLeadingConstraint,
            textGroupGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            textGroupGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleTopConstraint,
            subtitleTopConstraint,
            subtitleBottomConstraint,
            textGroupCenterConstraint,
            titleToShortcutConstraint,
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleToShortcutConstraint,
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    /// Workspace icons and SF Symbols contain very different transparent bearings. Scaling
    /// their full canvases into one square therefore produces visibly different icon sizes
    /// even when every constraint is identical. Minimal trims transparent padding, then uses
    /// a category-specific optical box. Native app and Settings artwork gets a true 35-point
    /// canvas, while the simpler action symbols stay quiet inside the original 30-point canvas.
    static func minimalIconCanvasSize(for kind: SearchKind) -> CGFloat {
        switch kind {
        case .application, .systemSetting, .webSearch:
            LauncherMinimalMetrics.resultNativeIconSize
        default:
            LauncherMinimalMetrics.resultIconSize
        }
    }

    static func liquidIconSize(for kind: SearchKind) -> CGFloat {
        LauncherLiquidGlassMetrics.resultIconSize
    }

    static func liquidOpticalIconSize(for kind: SearchKind) -> CGFloat {
        switch kind {
        case .action:
            LauncherLiquidGlassMetrics.resultActionIconOpticalSize
        case .clipboard:
            LauncherLiquidGlassMetrics.resultClipboardIconOpticalSize
        default:
            liquidIconSize(for: kind)
        }
    }

    /// Every Liquid row reserves one 50-point icon column. Action glyphs draw in their
    /// requested 30-point canvas centred inside it, keeping narrow symbols away from either
    /// column edge without changing the title alignment.
    static func liquidDrawingCanvasSize(for kind: SearchKind) -> CGFloat {
        kind == .action
            ? LauncherLiquidGlassMetrics.resultActionIconOpticalSize
            : LauncherLiquidGlassMetrics.resultIconSize
    }

    static func minimalOpticalIconSize(for kind: SearchKind) -> CGFloat {
        switch kind {
        case .application, .systemSetting, .webSearch:
            LauncherMinimalMetrics.resultNativeIconOpticalSize
        case .action:
            LauncherMinimalMetrics.resultActionIconOpticalSize
        default:
            LauncherMinimalMetrics.resultIconOpticalSize
        }
    }

    private static func normalizedIcon(
        _ source: NSImage,
        canvasSize: CGFloat,
        opticalSize: CGFloat
    ) -> NSImage {
        let samplePixels = 96
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: samplePixels,
            pixelsHigh: samplePixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return source }
        bitmap.size = source.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: source.size).fill()
        source.draw(
            in: NSRect(origin: .zero, size: source.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var minX = samplePixels
        var minY = samplePixels
        var maxX = -1
        var maxY = -1
        for y in 0..<samplePixels {
            for x in 0..<samplePixels {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.08
                else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY, source.size.width > 0, source.size.height > 0
        else { return source }

        let scaleX = source.size.width / CGFloat(samplePixels)
        let scaleY = source.size.height / CGFloat(samplePixels)
        let crop = NSRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )
        let fit = min(opticalSize / crop.width, opticalSize / crop.height)
        let drawnSize = NSSize(width: crop.width * fit, height: crop.height * fit)
        let destination = NSRect(
            x: (canvasSize - drawnSize.width) / 2,
            y: (canvasSize - drawnSize.height) / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )
        let normalized = NSImage(size: NSSize(width: canvasSize, height: canvasSize), flipped: false) { _ in
            source.draw(
                in: destination,
                from: crop,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        normalized.isTemplate = source.isTemplate
        return normalized
    }

    /// Clipboard's small handle and antialiased outer pixels are part of the symbol. Unlike
    /// action glyphs, fit its complete AppKit image bounds rather than trimming the alpha bounds.
    private static func fittedIconPreservingSourceBounds(
        _ source: NSImage,
        canvasSize: CGFloat,
        opticalSize: CGFloat
    ) -> NSImage {
        guard source.size.width > 0, source.size.height > 0 else { return source }
        let fit = min(opticalSize / source.size.width, opticalSize / source.size.height)
        let drawnSize = NSSize(width: source.size.width * fit, height: source.size.height * fit)
        let destination = NSRect(
            x: (canvasSize - drawnSize.width) / 2,
            y: (canvasSize - drawnSize.height) / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )
        let fitted = NSImage(size: NSSize(width: canvasSize, height: canvasSize), flipped: false) { _ in
            source.draw(
                in: destination,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        fitted.isTemplate = source.isTemplate
        return fitted
    }

    func configure(
        result: RankedResult,
        icon: NSImage,
        settingsBadge badge: NSImage? = nil,
        confirmation: Bool,
        row: Int,
        selected: Bool,
        theme: LauncherThemeDescriptor,
        shortcutSlot: Int? = nil
    ) {
        let usesMinimalLayout = theme.design == .minimal
        let usesLiquidGlassLayout = theme.design == .liquidGlass
        let isNoResults = result.entry.iconKey == "status:no-results"
        let usesCompactStatusIcon = isNoResults
            || (usesLiquidGlassLayout && result.entry.kind == .status)
        let templatePointSize: CGFloat = if usesCompactStatusIcon {
            Self.statusIconSize
        } else if usesMinimalLayout {
            LauncherMinimalMetrics.resultTemplatePointSize
        } else if usesLiquidGlassLayout {
            Self.liquidOpticalIconSize(for: result.entry.kind)
        } else {
            27
        }
        let templateWeight: NSFont.Weight = usesLiquidGlassLayout
            && result.entry.kind == .clipboard
            ? .medium
            : .regular
        let sourceIcon = if usesLiquidGlassLayout, result.entry.kind == .clipboard {
            NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: "Clipboard History"
            ) ?? icon
        } else {
            icon
        }
        let usesNativeArtwork = result.entry.kind == .application
            || result.entry.kind == .systemSetting
            || result.entry.kind == .file
        let configuredIcon = sourceIcon.isTemplate && !usesNativeArtwork
            ? (sourceIcon.withSymbolConfiguration(.init(
                pointSize: templatePointSize,
                weight: templateWeight
            )) ?? sourceIcon)
            : sourceIcon
        resultIcon.symbolConfiguration = nil
        resultIcon.contentTintColor = nil
        resultIcon.image = if usesCompactStatusIcon {
            Self.normalizedIcon(
                configuredIcon,
                canvasSize: Self.statusIconSize,
                opticalSize: Self.statusIconSize
            )
        } else if usesMinimalLayout {
            Self.normalizedIcon(
                configuredIcon,
                canvasSize: Self.minimalIconCanvasSize(for: result.entry.kind),
                opticalSize: Self.minimalOpticalIconSize(for: result.entry.kind)
            )
        } else if usesLiquidGlassLayout, result.entry.kind == .clipboard {
            Self.fittedIconPreservingSourceBounds(
                configuredIcon,
                canvasSize: Self.liquidIconSize(for: result.entry.kind),
                opticalSize: Self.liquidOpticalIconSize(for: result.entry.kind)
            )
        } else if usesLiquidGlassLayout, configuredIcon.isTemplate {
            Self.normalizedIcon(
                configuredIcon,
                canvasSize: Self.liquidDrawingCanvasSize(for: result.entry.kind),
                opticalSize: Self.liquidOpticalIconSize(for: result.entry.kind)
            )
        } else {
            configuredIcon
        }
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
        let shortcut = LauncherNumericShortcut.label(
            forRow: shortcutSlot ?? row,
            visibleResultCount: theme.visibleResultCount
        )
        let reservesShortcutColumn = theme.showsShortcuts && result.entry.kind != .status
        subtitleLabel.isHidden = !showsSubtitle
        shortcutLabel.isHidden = !reservesShortcutColumn
        titleTopConstraint.isActive = false
        subtitleTopConstraint.isActive = false
        subtitleBottomConstraint.isActive = false
        textGroupCenterConstraint.isActive = false
        titleCenterConstraint.isActive = false
        titleTopConstraint.isActive = showsSubtitle
        subtitleTopConstraint.isActive = showsSubtitle
        subtitleBottomConstraint.isActive = showsSubtitle
        textGroupCenterConstraint.isActive = showsSubtitle
        titleCenterConstraint.isActive = !showsSubtitle
        titleToShortcutConstraint.isActive = reservesShortcutColumn
        subtitleToShortcutConstraint.isActive = reservesShortcutColumn
        titleToEdgeConstraint.isActive = !reservesShortcutColumn
        subtitleToEdgeConstraint.isActive = !reservesShortcutColumn
        shortcutLabel.stringValue = shortcut ?? ""
        selectionColor = theme.selectionColor
        selectedTextColor = theme.selectedTextColor
        selectedShortcutTextColor = theme.selectedShortcutTextColor
        usesFullWidthSelectionBackground = theme.design == .minimal
        let minimalIconSize = Self.minimalIconCanvasSize(for: result.entry.kind)
        let minimalSlotSize = LauncherMinimalMetrics.resultNativeIconSize
        let minimalSlotExpansion = (
            minimalSlotSize - LauncherMinimalMetrics.resultIconSize
        ) / 2
        iconLeadingConstraint.constant = usesLiquidGlassLayout
            ? 8
            : (
                usesMinimalLayout
                    ? LauncherMinimalMetrics.resultContentLeadingInset - minimalSlotExpansion
                    : 4
            )
        let iconSlotSize = usesLiquidGlassLayout
            ? Self.liquidIconSize(for: result.entry.kind)
            : (usesMinimalLayout ? minimalSlotSize : 40)
        let iconDrawingSize = usesCompactStatusIcon
            ? Self.statusIconSize
            : (
                usesLiquidGlassLayout
                    ? Self.liquidDrawingCanvasSize(for: result.entry.kind)
                    : (usesMinimalLayout ? minimalIconSize : 40)
            )
        iconWidthConstraint.constant = iconSlotSize
        iconHeightConstraint.constant = iconSlotSize
        iconDrawingWidthConstraint.constant = iconDrawingSize
        iconDrawingHeightConstraint.constant = iconDrawingSize
        let showsSettingsBadge = result.entry.kind == .systemSetting && badge != nil
        settingsBadge.image = showsSettingsBadge ? badge : nil
        settingsBadge.isHidden = !showsSettingsBadge
        settingsBadgeSizeConstraint.constant = usesMinimalLayout
            ? LauncherMinimalMetrics.resultSettingsBadgeSize
            : LauncherLiquidGlassMetrics.resultSettingsBadgeSize
        titleLeadingConstraint.constant = usesLiquidGlassLayout
            ? 10
            : (
                usesMinimalLayout
                    ? LauncherMinimalMetrics.resultTitleLeadingInset - minimalSlotExpansion
                    : 4
            )
        titleLabel.font = .systemFont(
            ofSize: usesMinimalLayout ? LauncherMinimalMetrics.resultTitleFontSize : 17,
            weight: theme.design == .liquidGlass ? .regular : .medium
        )
        subtitleLabel.font = .systemFont(
            ofSize: usesMinimalLayout ? LauncherMinimalMetrics.resultSubtitleFontSize : 12,
            weight: .regular
        )
        shortcutLabel.font = .systemFont(
            ofSize: usesMinimalLayout ? LauncherMinimalMetrics.resultShortcutFontSize : 13,
            weight: .semibold
        )
        layer?.cornerRadius = theme.resultSelectionCornerRadius
        layer?.borderWidth = 0
        layer?.borderColor = nil
        setSelected(selected)
        setAccessibilityLabel(result.entry.title)
        setAccessibilityHelp(subtitleLabel.stringValue)
    }

    func setShortcutBadge(_ text: String?) {
        shortcutLabel.stringValue = text ?? ""
    }

    var isShowingSettingsBadge: Bool { !settingsBadge.isHidden }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        updateSelectionBackground()
        updateColors()
    }

    private func updateSelectionBackground() {
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = selected ? selectionColor.cgColor : NSColor.clear.cgColor
        }
        layer?.backgroundColor = usesFullWidthSelectionBackground ? NSColor.clear.cgColor : color

        var ancestor = superview
        while let view = ancestor, !(view is NSTableRowView) {
            ancestor = view.superview
        }
        guard let rowView = ancestor as? NSTableRowView else { return }
        rowView.wantsLayer = true
        rowView.layer?.backgroundColor = usesFullWidthSelectionBackground
            ? color
            : NSColor.clear.cgColor
        rowView.layer?.cornerRadius = 0
        rowView.layer?.borderWidth = 0
        rowView.layer?.borderColor = nil
    }

    private func updateColors() {
        let highlighted = selected || backgroundStyle == .emphasized
        titleLabel.textColor = highlighted ? selectedTextColor : .labelColor
        subtitleLabel.textColor = highlighted
            ? selectedTextColor.withAlphaComponent(0.82)
            : .secondaryLabelColor
        shortcutLabel.textColor = highlighted
            ? selectedShortcutTextColor
            : .tertiaryLabelColor
        // SF Symbol action icons are template images. Let AppKit apply semantic label colors
        // in Light, Dark, and selected states. Native full-color app/Settings bitmaps must not
        // inherit the table's emphasized backgroundStyle, which otherwise flattens pane art
        // into a white SF-symbol silhouette on the selected row.
        if resultIcon.image?.isTemplate == true {
            resultIcon.cell?.backgroundStyle = backgroundStyle
            resultIcon.contentTintColor = highlighted ? selectedTextColor : .labelColor
        } else {
            resultIcon.cell?.backgroundStyle = .normal
            resultIcon.contentTintColor = nil
        }
        resultIcon.applyNativeCompositing()
    }
}

/// Full-color application and Settings pane art sits inside the HUD material. Template
/// images keep vibrancy so semantic tints work. Native bitmaps must not: vibrancy punches
/// them into a white silhouette on the selected row. They also cannot draw into the row's
/// transparent selection layer, or the same HUD punch-out leaves an empty slot on every
/// unselected row. Give native artwork its own layer so it composites over the material.
private final class ResultIconView: NSImageView {
    override var allowsVibrancy: Bool {
        image?.isTemplate == true
    }

    override var image: NSImage? {
        get { super.image }
        set {
            super.image = newValue
            applyNativeCompositing()
        }
    }

    func applyNativeCompositing() {
        let usesNativeArtwork = image?.isTemplate == false
        wantsLayer = usesNativeArtwork
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = false
    }
}

/// A nonblocking eased progress driver for the launcher's height motion. `step` receives the
/// curved progress on the main run loop between events; `completion` runs only when the
/// motion finishes on its own, never after `stop()`.
final class LauncherPanelResizeAnimation: NSAnimation {
    private let step: @MainActor (CGFloat) -> Void
    private let completion: @MainActor () -> Void
    private var hasCompleted = false

    init(
        duration: TimeInterval,
        step: @escaping @MainActor (CGFloat) -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        self.step = step
        self.completion = completion
        super.init(duration: duration, animationCurve: .easeInOut)
        animationBlockingMode = .nonblocking
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // A `.nonblocking` animation advances on the main run loop.
    override var currentProgress: NSAnimation.Progress {
        didSet {
            let value = CGFloat(currentValue)
            // NSAnimation ends itself when progress reaches 1; `stop()` never gets here.
            let finished = currentProgress >= 1 && !hasCompleted
            if finished { hasCompleted = true }
            let step = step
            let completion = completion
            MainActor.assumeIsolated {
                step(value)
                if finished { completion() }
            }
        }
    }
}

@MainActor
final class LauncherPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private static let panelWidth = LauncherMinimalMetrics.width
    private static let searchHeight = LauncherMinimalMetrics.searchHeight
    private static let maximumPreparedResultRows = LauncherSearchLimits.resultSetCap
    private let panel: LauncherPanel
    private let nativeSearchField = LauncherNativeSearchField()
    // The live launcher contains a real editable search control, while its enclosing glass
    // stays passive to avoid AppKit's transient rectangular click-response lens.
    private let liquidGlassSurface = LauncherLiquidGlassSurfaceView(interactive: true)
    private let headerSeparator = LauncherHeaderSeparatorView()
    private let tableView = NSTableView()
    private let scrollView = LauncherResultsScrollView()
    private let preparedResultRows: [ResultRowView]
    private let iconCache: IconCache
    private let themeController = LauncherThemeController()
    private let environmentProvider: @MainActor () -> LauncherAppearanceEnvironment
    private var needsPresentationIconRefresh = false
    private var lastNativeIconRefreshContext: IconRenderContext?
    private var theme: LauncherThemeDescriptor {
        didSet {
            panel.numericShortcutLimit = LauncherNumericShortcut.limit(
                visibleResultCount: theme.visibleResultCount
            )
        }
    }
    private var retainedContentView: NSView?
    private var results: [RankedResult] = []
    private var inlineSuggestion: RankedResult?
    private var confirmationEntryID: String?
    private var isProgrammaticallyHiding = false
    private var pendingAppearance: LauncherAppearancePreferences?
    private var appliedAppearance: LauncherAppearancePreferences?
    private var contentConstraints: [NSLayoutConstraint] = []
    private var resultsTopConstraint: NSLayoutConstraint?
    private var resultsBottomConstraint: NSLayoutConstraint?
    /// Replaces the bottom constraint while a growth reveals rows or a full collapse clips them.
    private var resultsMotionHeightConstraint: NSLayoutConstraint?
    private var currentMode: LauncherMode = .main
    private var presentationSessionActive = false
    /// Liquid Glass starts as one compact search capsule. Any useful match opens one stable
    /// result viewport so a single Finder/application result is never hidden in the header.
    private var liquidResultsExpanded = false
    private var arrowRepeatGate = LauncherArrowRepeatGate()
    /// The newest committed geometry whose motion has not started yet. Result changes coalesce
    /// here so a burst of keystrokes schedules one transition instead of one per key.
    private var pendingExpansionTarget: NSRect?
    /// The rows already on screen stay mounted while a collapse clips them away. Clearing
    /// them first left an empty expanded surface, and only then did the window shrink.
    /// A shorter list keeps its surplus rows here until that clip finishes.
    private var holdsRowsForCollapse = false
    private var rowsHeldForClip: [RankedResult] = []
    private var expansionFlush: DispatchWorkItem?
    private var resizeAnimation: LauncherPanelResizeAnimation?
    private let expansionAnimationDuration: (@MainActor () -> TimeInterval)?
    /// Last sampled motion duration. apply() must not sample the environment on every
    /// keystroke; this refreshes wherever the environment is already being read.
    private var cachedExpansionAnimationDuration: TimeInterval = 0
    /// Used so a new query can pin the table to the top without wiping the user's scroll
    /// offset on every result delivery for the same query.
    private var lastAppliedQuery: String?
    /// True while Window Server is tracking a chrome-initiated `performDrag(with:)`.
    /// AppKit may swallow the matching mouse-up, so monitors and a button-state poll
    /// both call `finishNativeWindowDrag()`.
    private var isNativeWindowDragActive = false
    private var nativeDragLocalMouseUpMonitor: Any?
    private var nativeDragGlobalMouseUpMonitor: Any?
    private var nativeDragEndPoll: Timer?

    private var searchField: NSTextField { nativeSearchField }

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
    var onOriginCommitted: ((Double, Double) -> Void)?

    init(
        environmentProvider: @escaping @MainActor () -> LauncherAppearanceEnvironment = { .current },
        expansionAnimationDuration: (@MainActor () -> TimeInterval)? = nil
    ) {
        self.environmentProvider = environmentProvider
        self.expansionAnimationDuration = expansionAnimationDuration
        iconCache = IconCache()
        preparedResultRows = (0..<Self.maximumPreparedResultRows).map { _ in
            let row = ResultRowView()
            row.identifier = ResultRowView.identifier
            return row
        }
        theme = LauncherThemeController().descriptor(for: .defaults(design: .minimal), environment: environmentProvider())
        panel = LauncherPanel(
            contentRect: NSRect(
                origin: Self.automatedTestOrigin,
                size: NSSize(width: Self.panelWidth, height: Self.searchHeight)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.numericShortcutLimit = LauncherNumericShortcut.limit(
            visibleResultCount: theme.visibleResultCount
        )
        super.init()
        cachedExpansionAnimationDuration = effectiveExpansionAnimationDuration
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
    var searchPlaceholder: String? { nativeSearchField.centeredPlaceholderAttributedString?.string }
    var usesNativeSearchField: Bool { searchField is LauncherNativeSearchField }
    var resultsAccessibilityLabel: String? { tableView.accessibilityLabel() }
    var isContentViewAttached: Bool {
        panel.contentView != nil && panel.contentView === retainedContentView
    }
    var isSearchSurfaceWindowBacked: Bool { liquidGlassSurface.window === panel }
    var isResultViewportVisible: Bool { !scrollView.isHidden }
    /// Rows still in the table, including surplus kept only so a shrink can clip them.
    var mountedResultRowCount: Int { tableView.numberOfRows }
    /// True while a sanctioned height transition is scheduled, coalescing, or in flight.
    var isExpansionAnimationInFlight: Bool {
        resizeAnimation != nil || pendingExpansionTarget != nil
    }
    var listedResultIDs: [String] { results.map(\.entry.id) }
    var selectedResultRow: Int { tableView.selectedRow }
    var resultsScrollOffset: CGFloat { scrollView.contentView.bounds.origin.y }
    var resultsVisibleRect: NSRect { tableView.visibleRect }
    var selectedResultID: String? {
        guard results.indices.contains(tableView.selectedRow) else { return nil }
        return results[tableView.selectedRow].entry.id
    }
    var inlineSuggestionText: String? {
        inlineSuggestion.map {
            LauncherInlineSuggestionManager.displayText(for: $0, query: searchField.stringValue)
        }
    }
    var currentPanelHeight: CGFloat {
        max(0, panel.frame.height)
    }

    func applyAppearance(
        _ preferences: LauncherAppearancePreferences,
        force: Bool = false
    ) {
        let environment = environmentProvider()
        cachedExpansionAnimationDuration = effectiveExpansionAnimationDuration
        let next = themeController.descriptor(for: preferences, environment: environment)
        let sameLayout = appliedAppearance?.hasSameLayout(as: preferences) == true
            && (next.surface == theme.surface || preferences.design == .minimal)
        if sameLayout {
            guard force || appliedAppearance != preferences || theme.environment != next.environment else { return }
            pendingAppearance = nil
            appliedAppearance = preferences
            applyVisualAppearance(next)
        } else if panel.isVisible {
            // Structural changes wait until dismissal; foreground appearance still updates.
            pendingAppearance = preferences
            if var visiblePreferences = appliedAppearance {
                visiblePreferences.mode = preferences.mode
                let visibleTheme = themeController.descriptor(for: visiblePreferences, environment: environment)
                if visibleTheme.surface == theme.surface { applyVisualAppearance(visibleTheme) }
            }
        } else {
            applyAppearanceNow(preferences, descriptor: next)
        }
    }

    private func applyVisualAppearance(_ next: LauncherThemeDescriptor) {
        theme = next
        panel.appearance = theme.appearance
        searchField.textColor = theme.searchTextColor
        // Updating foreground attributes does not replace the field editor or its marked text.
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.textColor = theme.searchTextColor
            editor.insertionPointColor = .textColor
        }
        if let surface = retainedContentView?.subviews.first {
            (surface as? LauncherMinimalMaterialSurfaceView)?.updateAppearance(
                isDark: theme.isDark, opaqueBackground: theme.surface == .opaque ? theme.backgroundColor : nil)
            surface.effectiveAppearance.performAsCurrentDrawingAppearance {
                if theme.surface == .opaque { surface.layer?.backgroundColor = theme.backgroundColor.cgColor }
            }
        }
        headerSeparator.color = theme.headerSeparatorColor
        LauncherNativeSearchFieldStyle.apply(
            to: nativeSearchField,
            metrics: theme.searchMetrics,
            iconColor: theme.searchIconColor,
            placeholderColor: theme.searchPlaceholderColor
        )
        applyAdditiveInk()
        updateModeChrome()
        nativeSearchField.needsDisplay = true
        iconCache.prewarm(
            results.map(\.entry),
            limit: LauncherSearchLimits.iconPrewarmCap,
            context: iconContext
        )
        for row in results.indices where row < preparedResultRows.count {
            _ = tableView(tableView, viewFor: tableView.tableColumns.first, row: row)
        }
        panel.contentView?.needsDisplay = true
    }

    private var iconContext: IconRenderContext {
        let context = theme.iconContext
        return IconRenderContext(appearance: context.appearance,
            increasesContrast: context.increasesContrast, pointSize: context.pointSize,
            backingScale: panel.screen?.backingScaleFactor ?? context.backingScale)
    }

    func refreshDisplayedNativeIcons() {
        guard panel.isVisible else { return }
        let context = iconContext
        let entries = iconEntriesNearViewport
        // Native artwork is cached per appearance, contrast, size and scale, so an unchanged
        // context has nothing to re-sample. Re-materializing every near-viewport icon on each
        // presentation was the launch-time convoy that delayed the rows being looked at.
        guard lastNativeIconRefreshContext != context else {
            iconCache.refreshProvisionalIcons(entries, context: context)
            return
        }
        lastNativeIconRefreshContext = context
        iconCache.refreshNativeIcons(entries, context: context)
    }

    /// Icons for the on-screen rows plus a small buffer so scrolling does not flash placeholders.
    private var iconEntriesNearViewport: [SearchEntry] {
        let visible = tableView.rows(in: tableView.visibleRect)
        if visible.length > 0 {
            let start = max(results.startIndex, visible.location - 2)
            let end = min(results.endIndex, visible.location + visible.length + 2)
            return results[start..<end].map(\.entry)
        }
        let fallbackCount = min(results.count, theme.visibleResultCount + 2)
        return results.prefix(fallbackCount).map(\.entry)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let appliedAppearance else { return }
        applyAppearance(appliedAppearance, force: true)
    }

    private func applyAppearanceNow(_ preferences: LauncherAppearancePreferences, descriptor: LauncherThemeDescriptor? = nil) {
        let oldFrame = panel.frame
        cancelPendingPanelMotion()
        pendingAppearance = nil
        appliedAppearance = preferences
        theme = descriptor ?? themeController.descriptor(for: preferences, environment: environmentProvider())
        cachedExpansionAnimationDuration = effectiveExpansionAnimationDuration
        panel.appearance = theme.appearance
        panel.hasShadow = theme.hasShadow
        tableView.rowHeight = theme.rowHeight
        // Resize both axes before installing the constrained content tree. A controller is
        // born at Minimal's width; installing Liquid Glass inside that stale frame makes
        // AppKit break the content-width constraint while the hidden launcher is prepared.
        // Detach that old constrained tree first; structural changes are queued while visible,
        // so this replacement always occurs while the panel is safely ordered out.
        panel.contentView = nil
        retainedContentView = nil
        let height = desiredPanelHeight
        let preparedFrame = NSRect(
            x: oldFrame.midX - theme.width / 2,
            y: oldFrame.maxY - height,
            width: theme.width,
            height: height
        )
        panel.setFrame(preparedFrame, display: false)
        configureContent()
        if panel.isVisible { position(on: panel.screen) }
    }

    func setMode(_ mode: LauncherMode, initialQuery: String = "") {
        currentMode = mode
        liquidResultsExpanded = false
        confirmationEntryID = nil
        searchField.stringValue = initialQuery
        inlineSuggestion = nil
        updateInlineSuggestionPresentation()
        updateModeChrome()
        focusSearchField()
    }

    func prepareIcons(for entries: [SearchEntry], resolveNativeSettings: Bool = true) {
        iconCache.prewarm(
            entries,
            limit: LauncherSearchLimits.iconPrewarmCap,
            context: iconContext,
            resolveNativeSettings: resolveNativeSettings
        )
    }

    /// Origin used before the first live `show(on:)` and for AppKit tests. AppKit's default
    /// `(0, 0)` is the bottom-left of the desktop; constructing or interrupting a test panel
    /// must not flash the Minimal capsule there.
    static let automatedTestOrigin = NSPoint(x: -16_000, y: -16_000)

    func show(on screen: NSScreen?) {
        present(on: screen, origin: nil)
    }

    /// Presents a real key window off-screen so tests can use the field editor without
    /// placing the launcher on the developer's desktop.
    func showForAutomatedTests() {
        present(on: nil, origin: Self.automatedTestOrigin)
    }

    private func present(on screen: NSScreen?, origin: NSPoint?) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }
        if let appliedAppearance { applyAppearance(appliedAppearance) }
        needsPresentationIconRefresh = true
        presentationSessionActive = true
        liquidResultsExpanded = false
        // Keep Liquid Glass window-backed while hidden. Reattaching the effect hierarchy in
        // the same transaction as orderFront leaves AppKit no committed backdrop in which to
        // prepare its glass sampling, so the global-hotkey presentation can appear opaque.
        if panel.contentView !== retainedContentView {
            panel.contentView = retainedContentView
        }
        searchField.stringValue = ""
        holdsRowsForCollapse = false
        rowsHeldForClip = []
        results = []
        lastAppliedQuery = nil
        inlineSuggestion = nil
        updateInlineSuggestionPresentation()
        tableView.reloadData()
        resetTableScrollPosition()
        updateResultsGeometry()
        resizePanel(to: desiredPanelHeight, display: false)
        confirmationEntryID = nil
        onQueryChanged?("")
        if let origin {
            var frame = panel.frame
            frame.origin = origin
            panel.setFrame(frame, display: false)
        } else {
            position(on: screen ?? NSScreen.main ?? NSScreen.screens.first)
        }
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        if panel.hasShadow { panel.invalidateShadow() }
        panel.makeKeyAndOrderFront(nil)
        focusSearchField(movingCaretToEnd: true)
        // Menu tracking and Space transitions can delay key-window commitment even for a
        // non-activating panel. Reassert the field editor on the next AppKit turn without
        // changing which application is active.
        DispatchQueue.main.async { [weak self] in
            self?.restoreSearchFocusIfVisible()
        }
    }

    /// Reasserts the field responder after AppKit commits a delayed key-window transition.
    func restoreSearchFocusIfVisible() {
        guard panel.isVisible else { return }
        if !panel.isKeyWindow { panel.makeKey() }
        focusSearchField(movingCaretToEnd: false)
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
        isProgrammaticallyHiding = true
        if isNativeWindowDragActive {
            finishNativeWindowDrag()
        }
        // Drop any pending or in-flight height motion before the panel leaves the screen;
        // the next presentation reuses this controller with fresh geometry.
        holdsRowsForCollapse = false
        rowsHeldForClip = []
        cancelPendingPanelMotion()
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
        // Search completions can arrive inside another AppKit animation context. All row,
        // glass, and window changes belong to one nonanimated update, including selection.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }
        let selectedEntryID: String? = if preservingSelection,
                                          self.results.indices.contains(tableView.selectedRow) {
            self.results[tableView.selectedRow].entry.id
        } else {
            nil
        }
        inlineSuggestion = currentMode == .main
            ? LauncherInlineSuggestionManager.suggestion(from: results)
            : nil
        let listedResults = results.filter {
            $0.entry.id != inlineSuggestion?.entry.id
        }
        // A status row cannot be selected. Showing one would open the result area with
        // nothing to act on, which is what “Continue typing” and “No files found” did.
        let hasSelectableResult = listedResults.contains { $0.entry.kind != .status }
        let visibleResults = hasSelectableResult
            ? Array(listedResults.prefix(LauncherSearchLimits.resultSetCap))
            : []
        // Spotlight keeps its initial Liquid Glass presentation as a single search capsule.
        // Recent results remain available to the other designs and specialized modes, but the
        // main Liquid Glass launcher expands only after the user supplies a query.
        let suppressesEmptyMainResults = theme.design == .liquidGlass
            && currentMode == .main
            && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let query = searchField.stringValue
        let shouldResetScroll = query != lastAppliedQuery
        lastAppliedQuery = query
        let nextResults = suppressesEmptyMainResults ? [] : visibleResults
        let mountedResults = self.results + rowsHeldForClip
        let canClipRows = panel.isVisible && cachedExpansionAnimationDuration > 0
        let retainsRows = canClipRows && !mountedResults.isEmpty && nextResults.isEmpty
        holdsRowsForCollapse = retainsRows
        if retainsRows, !rowsHeldForClip.isEmpty {
            // A full collapse clips every row that is already on screen, including surplus
            // from a shrink that has not finished.
            self.results = mountedResults
            rowsHeldForClip = []
        } else if !retainsRows {
            rowsHeldForClip = canClipRows && nextResults.count < mountedResults.count
                ? Array(mountedResults.dropFirst(nextResults.count))
                : []
        }
        updateInlineSuggestionPresentation()
        if retainsRows {
            // Leave the mounted rows in place. The shrinking window clips them, and the
            // table is cleared when that motion ends.
            updateLiquidPresentationState()
        } else {
            self.results = nextResults
            updateLiquidPresentationState()
            if !self.results.contains(where: { $0.entry.id == confirmationEntryID }) {
                confirmationEntryID = nil
            }
            if inlineSuggestion != nil, selectedEntryID == nil {
                tableView.deselectAll(nil)
                tableView.reloadData()
                refreshSelectionAppearance()
            } else {
                // Select before reloading. A reload that finds no selection builds every
                // row unselected, and the accent then disappears and returns a moment later.
                reloadResultsPreservingSelection(selectedEntryID)
            }
            if shouldResetScroll {
                resetTableScrollPosition()
            } else {
                scrollSelectedRowVisible()
            }
        }
        updateHeight()
        if needsPresentationIconRefresh, !results.isEmpty {
            needsPresentationIconRefresh = false
            refreshDisplayedNativeIcons()
        }
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count + rowsHeldForClip.count
    }

    private func displayedResult(at row: Int) -> RankedResult? {
        if results.indices.contains(row) { return results[row] }
        let heldIndex = row - results.count
        guard rowsHeldForClip.indices.contains(heldIndex) else { return nil }
        return rowsHeldForClip[heldIndex]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let result = displayedResult(at: row), preparedResultRows.indices.contains(row) else {
            return nil
        }
        // Views are prepared up to the bounded result-set cap so scrolling beyond the
        // viewport never allocates row chrome on the first keystroke.
        let view = preparedResultRows[row]
        let isHeldRow = !results.indices.contains(row)
        let icon = iconCache.image(for: result.entry, context: iconContext)
        view.configure(
            result: result,
            icon: icon,
            settingsBadge: result.entry.kind == .systemSetting
                ? iconCache.systemSettingsBadge(for: icon, context: iconContext)
                : nil,
            confirmation: confirmationEntryID == result.entry.id,
            row: row,
            selected: !isHeldRow && tableView.selectedRow == row,
            theme: theme,
            shortcutSlot: isHeldRow ? LauncherNumericShortcut.maximum : row - firstFullyVisibleResultRow()
        )
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        confirmationEntryID = nil
        refreshSelectionAppearance()
        updateHeaderSeparatorVisibility()
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
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            let movingUp = commandSelector == #selector(NSResponder.moveUp(_:))
            guard arrowRepeatGate.allow(isRepeat: NSApp.currentEvent?.isARepeat == true) else { return true }
            handle(movingUp ? .up : .down)
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
        guard !isProgrammaticallyHiding else { return }
        // A click in another application already chose the next owner of focus. Hide the
        // launcher without reactivating the application that preceded Command-Space.
        dismiss(notify: false)
    }

    func windowDidMove(_ notification: Notification) {
        // `performDrag(with:)` returns immediately. If the drag already ended without a
        // delivered mouse-up, the last move is the signal to persist origin.
        finishNativeWindowDragIfMouseIsUp()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSearchField(movingCaretToEnd: false)
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = "Broccoli Launcher"
        panel.setAccessibilityLabel("Broccoli Launcher")
        panel.appearance = theme.appearance
        panel.hasShadow = theme.hasShadow
        panel.animationBehavior = .none
        // Like Spotlight, the launcher accepts keyboard focus without activating Broccoli.
        // This prevents the previously active app's field editor from receiving characters
        // while macOS completes an asynchronous application-activation transition.
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Resignation is handled explicitly by windowDidResignKey. Automatic panel hiding can
        // happen before that delegate callback and leave isVisible out of sync with the launch
        // session, causing the next global shortcut to restore an old app instead of opening.
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.delegate = self
        panel.onCommand = { [weak self] command in self?.handle(command) }
        panel.onPotentialMove = { [weak self] event in
            self?.handlePotentialMove(with: event) ?? false
        }
    }

    private func configureContent() {
        // These controls survive a structural theme change. Removing them from a parent
        // does not remove their own height/width constraints, so retire our previous layout.
        NSLayoutConstraint.deactivate(contentConstraints)
        resultsMotionHeightConstraint?.isActive = false
        nativeSearchField.removeFromSuperview()
        liquidGlassSurface.removeFromSuperview()
        headerSeparator.removeFromSuperview()
        scrollView.removeFromSuperview()
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        // NSWindow derives a fitting size from constraints installed directly below its
        // content view. A constrained effect view previously became that root, so
        // AppKit repeatedly collapsed the 432-point panel to the search field's 70-point
        // minimum. Keep the window boundary frame-based and put all constrained content one
        // level below it. The host has no intrinsic size and always follows the panel frame.
        let host = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        if theme.surface == .glass {
            // The window shadow follows the composited window contents. The glass surface
            // clips everything it draws to its rounded outline, so rectangular corner pixels
            // never reach WindowServer. Clipping the host as well would antialias that edge
            // a second time and thin the Dark rim along the arcs.
            host.wantsLayer = true
        }

        // The material surface and the native window shadow must share the same boundary. An
        // inset surface inside a larger transparent window produces a separated outer rim.
        let surfaceFrame = host.bounds
        let surface: NSView
        switch theme.surface {
        case .glass:
            liquidGlassSurface.frame = surfaceFrame
            liquidGlassSurface.layoutSubtreeIfNeeded()
            liquidGlassSurface.setContentView(content)
            surface = liquidGlassSurface
        case .ultraThick, .opaque:
            let material = LauncherMinimalMaterialSurfaceView(
                frame: host.bounds,
                isDark: theme.isDark,
                opaqueBackground: theme.surface == .opaque ? theme.backgroundColor : nil
            )
            material.setContentView(content)
            surface = material
        }
        surface.frame = surfaceFrame
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        if theme.surface != .glass, theme.surface != .ultraThick {
            surface.wantsLayer = true
            surface.layer?.backgroundColor = theme.surface == .opaque
                ? theme.backgroundColor.cgColor
                : nil
            surface.layer?.cornerRadius = theme.cornerRadius
            surface.layer?.cornerCurve = theme.design == .minimal ? .circular : .continuous
            // The material and shadow already separate the launcher from the desktop, so an
            // additional painted outline would break the shared borderless geometry.
            surface.layer?.borderWidth = 0
            surface.layer?.borderColor = nil
            surface.layer?.masksToBounds = true
        }
        host.addSubview(surface)
        retainedContentView = host
        // A hidden NSWindow may safely retain its content hierarchy. Native glass needs this
        // persistent window association so its backdrop is ready before the next hotkey.
        panel.contentView = host

        let searchField = self.searchField
        searchField.translatesAutoresizingMaskIntoConstraints = false
        nativeSearchField.setCenteredPlaceholder(nil)
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.usesSingleLineMode = true
        searchField.focusRingType = .none
        LauncherNativeSearchFieldStyle.apply(
            to: nativeSearchField,
            metrics: theme.searchMetrics,
            iconColor: theme.searchIconColor,
            placeholderColor: theme.searchPlaceholderColor
        )
        searchField.textColor = theme.searchTextColor
        searchField.setAccessibilityLabel("Search Broccoli")
        searchField.setAccessibilityHelp("Type to search applications, settings, and actions")
        searchField.delegate = self
        content.addSubview(searchField)
        panel.initialFirstResponder = searchField

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
        // Wheel and trackpad input walks the selection instead of pixel-scrolling. The scroll
        // view still clips the result list and reveals the next row once the highlight is
        // already on the first or last visible slot.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
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
        let resultInsets = theme.resultVerticalInsets(resultCount: hasResults ? results.count : 0)
        let resultsTopConstraint = resultsChrome.topAnchor.constraint(
            equalTo: content.topAnchor,
            constant: theme.searchHeight + resultInsets.top
        )
        let resultsBottomConstraint = resultsChrome.bottomAnchor.constraint(
            equalTo: content.bottomAnchor,
            constant: -resultInsets.bottom
        )
        self.resultsTopConstraint = resultsTopConstraint
        self.resultsBottomConstraint = resultsBottomConstraint
        resultsMotionHeightConstraint = resultsChrome.heightAnchor.constraint(equalToConstant: 0)
        scrollView.isHidden = !hasResults
        let searchChrome: NSView = searchField
        let searchHeightConstraint = searchChrome.heightAnchor.constraint(
            equalToConstant: theme.searchHeight - theme.searchControlVerticalInset * 2)
        searchHeightConstraint.identifier = "Broccoli.searchHeight"
        var constraints = [
            searchChrome.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -theme.searchHorizontalInset
            ),
            // This is the AppKit equivalent of CSS center alignment: theme height changes do
            // not require separate icon, placeholder, or baseline corrections.
            searchChrome.centerYAnchor.constraint(
                equalTo: content.topAnchor,
                constant: theme.searchHeight / 2
            ),
            searchHeightConstraint,
            resultsChrome.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: theme.resultHorizontalInset),
            resultsTopConstraint,
            resultsBottomConstraint,
            searchChrome.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: theme.searchHorizontalInset
            ),
        ]
        constraints.append(resultsChrome.trailingAnchor.constraint(
            equalTo: content.trailingAnchor,
            constant: -theme.resultHorizontalInset
        ))
        if theme.showsHeaderSeparator {
            headerSeparator.translatesAutoresizingMaskIntoConstraints = false
            headerSeparator.color = theme.headerSeparatorColor
            headerSeparator.lineThickness = theme.headerSeparatorThickness
            headerSeparator.angleDegrees = theme.headerSeparatorAngleDegrees
            headerSeparator.isHidden = !theme.shouldShowHeaderSeparator(
                hasResults: hasResults,
                selectedRow: tableView.selectedRow
            )
            content.addSubview(headerSeparator)
            constraints += [
                headerSeparator.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor,
                    constant: theme.headerSeparatorLeadingInset
                ),
                headerSeparator.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -theme.headerSeparatorTrailingInset
                ),
                headerSeparator.topAnchor.constraint(
                    equalTo: content.topAnchor,
                    constant: theme.headerSeparatorTopInset
                ),
                headerSeparator.heightAnchor.constraint(
                    equalToConstant: theme.headerSeparatorLayoutHeight
                ),
            ]
        }
        contentConstraints = constraints
        NSLayoutConstraint.activate(contentConstraints)
        applyAdditiveInk()
        updateModeChrome()
        updateInlineSuggestionPresentation()
        tableView.rowHeight = theme.rowHeight
        tableView.reloadData()
        resetTableScrollPosition()
        refreshSelectionAppearance()
        updateHeaderSeparatorVisibility()
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
            scrollSelectedRowVisible()
        case .down:
            revealCompactLiquidResultsIfNeeded()
            guard let row = LauncherSelection.nextRow(
                currentRow: tableView.selectedRow,
                movingUp: false,
                results: results
            ) else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            scrollSelectedRowVisible()
        case .execute:
            if results.indices.contains(tableView.selectedRow) {
                onExecute?(results[tableView.selectedRow])
            } else if let inlineSuggestion, inlineSuggestion.entry.target != .none {
                onExecute?(inlineSuggestion)
            }
        case .reveal:
            let row = max(0, tableView.selectedRow)
            guard results.indices.contains(row) else { return }
            onReveal?(results[row])
        case .preferences:
            onPreferences?()
        case .executeIndex(let slot):
            let row = firstFullyVisibleResultRow() + slot
            guard slot < LauncherNumericShortcut.limit(visibleResultCount: theme.visibleResultCount),
                  results.indices.contains(row),
                  results[row].entry.kind != .status else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            refreshSelectionAppearance()
            onExecute?(results[row])
        case .dismiss:
            if let onCancel { onCancel() } else { dismiss() }
        }
    }

    private func focusSearchField(movingCaretToEnd: Bool = true) {
        guard panel.isVisible else { return }
        let previousSelection = (searchField.currentEditor() as? NSTextView)?.selectedRange()
        guard panel.makeFirstResponder(searchField) else { return }
        nativeSearchField.configureCurrentFieldEditor()
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = theme.searchTextColor
        editor.textColor = theme.searchTextColor
        editor.backgroundColor = .clear
        if movingCaretToEnd {
            editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
        } else if let previousSelection,
                  NSMaxRange(previousSelection) <= editor.string.utf16.count {
            editor.selectedRange = previousSelection
        }
    }

    private func applyAdditiveInk() {
        LauncherAdditiveInk.apply(theme.usesAdditiveInk, to: nativeSearchField)
        LauncherAdditiveInk.apply(theme.usesAdditiveInk, to: headerSeparator)
    }

    private func updateModeChrome() {
        let placeholder: String
        let accessibilityLabel: String
        switch currentMode {
        case .main:
            nativeSearchField.setScope(nil)
            placeholder = "Search Broccoli"
            accessibilityLabel = "Search Broccoli"
        case .fileSearch:
            nativeSearchField.setScope("Files")
            placeholder = "Search names and paths"
            accessibilityLabel = "Search Files"
        case .clipboard:
            nativeSearchField.setScope("Clipboard")
            placeholder = "Filter history"
            accessibilityLabel = "Search Clipboard History"
        }
        searchField.setAccessibilityLabel(accessibilityLabel)
        nativeSearchField.setCenteredPlaceholder(
            LauncherNativeSearchFieldStyle.placeholder(
                placeholder,
                metrics: nativeSearchField.searchMetrics,
                color: theme.searchPlaceholderColor
            )
        )
    }

    private func updateInlineSuggestionPresentation() {
        nativeSearchField.setInlineSuggestion(
            inlineSuggestion.map {
                LauncherInlineSuggestionManager.displayText(
                    for: $0,
                    query: searchField.stringValue
                )
            },
            color: .secondaryLabelColor,
            accessibilityLabel: inlineSuggestion.map {
                LauncherInlineSuggestionManager.accessibilityLabel(
                    for: $0,
                    query: searchField.stringValue
                )
            }
        )
    }

    private func updateHeight() {
        updateResultsGeometry()
        resizePanel(to: desiredPanelHeight, display: true)
    }

    private var desiredPanelHeight: CGFloat {
        if holdsRowsForCollapse {
            return theme.searchHeight
        }
        if theme.design == .liquidGlass,
           currentMode == .main,
           !presentsResultViewport {
            return theme.searchHeight
        }
        return theme.panelHeight(resultCount: results.count)
    }

    private var presentsResultViewport: Bool {
        guard !results.isEmpty else { return false }
        guard theme.design == .liquidGlass, currentMode == .main else { return true }
        return liquidResultsExpanded
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
        // A match is useful only when it is visibly presented. Always open the result region
        // for a non-empty query, including the common single-result Finder/application case.
        liquidResultsExpanded = !results.isEmpty
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

    private func scrollSelectedRowVisible() {
        let row = tableView.selectedRow
        guard results.indices.contains(row) else { return }
        let unit = theme.rowHeight + theme.rowSpacing
        guard unit > 0 else { return }
        let visibleCount = max(1, theme.visibleResultCount)
        let currentFirst = alignedFirstVisibleRow(unit: unit)
        let targetFirst: Int
        if row < currentFirst {
            targetFirst = row
        } else if row > currentFirst + visibleCount - 1 {
            targetFirst = row - visibleCount + 1
        } else {
            targetFirst = currentFirst
        }
        let maxFirst = max(0, results.count - visibleCount)
        let originY = CGFloat(min(max(0, targetFirst), maxFirst)) * unit
        if abs(scrollView.contentView.bounds.origin.y - originY) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: originY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        refreshShortcutBadges()
    }

    /// ⌘1 is whichever result is in the top slot. Only the badge text changes.
    private func refreshShortcutBadges() {
        let first = firstFullyVisibleResultRow()
        for row in results.indices {
            guard let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultRowView else { continue }
            let text = results[row].entry.kind == .status
                ? nil
                : LauncherNumericShortcut.label(
                    forRow: row - first,
                    visibleResultCount: theme.visibleResultCount
                )
            view.setShortcutBadge(text)
        }
    }

    private func alignedFirstVisibleRow(unit: CGFloat) -> Int {
        Int((scrollView.contentView.bounds.origin.y / unit).rounded())
    }

    private func firstFullyVisibleResultRow() -> Int {
        let unit = theme.rowHeight + theme.rowSpacing
        guard unit > 0 else { return 0 }
        return min(max(0, alignedFirstVisibleRow(unit: unit)), max(0, results.count - 1))
    }

    private func updateResultsGeometry() {
        // While a collapse is clipping the current rows, keep the insets and the divider
        // where they were. Recomputing them for an empty query lifts the list and removes
        // the line before the window has shrunk.
        let hasResults = holdsRowsForCollapse || presentsResultViewport
        let insets = theme.resultVerticalInsets(resultCount: hasResults ? results.count : 0)
        resultsTopConstraint?.constant = theme.searchHeight + insets.top
        resultsBottomConstraint?.constant = -insets.bottom
        if holdsRowsForCollapse {
            if resultsMotionHeightConstraint?.isActive == false, !scrollView.isHidden {
                setResultsViewportMotionHeight(scrollView.frame.height)
            }
        } else {
            setResultsViewportMotionHeight(nil)
        }
        scrollView.isHidden = !hasResults
        updateHeaderSeparatorVisibility()
    }

    /// While the window grows or fully collapses, the viewport keeps a fixed height, so the
    /// window's rounded bottom edge is the only thing that reveals or clips the rows. Pinned
    /// above that edge, the viewport cut the rows along a second, straight line, and its
    /// insets made AppKit enlarge a compact window to their minimum height before a growth
    /// began, so the divider appeared on an empty strip that then opened beneath it.
    private func setResultsViewportMotionHeight(_ height: CGFloat?) {
        guard let pinned = resultsBottomConstraint,
              let fixed = resultsMotionHeightConstraint
        else { return }
        if let height {
            fixed.constant = max(0, height)
            guard !fixed.isActive else { return }
            NSLayoutConstraint.deactivate([pinned])
            NSLayoutConstraint.activate([fixed])
        } else if fixed.isActive {
            NSLayoutConstraint.deactivate([fixed])
            NSLayoutConstraint.activate([pinned])
        }
    }

    private func updateHeaderSeparatorVisibility() {
        headerSeparator.isHidden = !theme.shouldShowHeaderSeparator(
            hasResults: holdsRowsForCollapse || presentsResultViewport,
            selectedRow: tableView.selectedRow
        )
        updateHeaderSeparatorFade()
    }

    /// The divider fades across the top result inset: in as a growth opens it and out as a
    /// collapse closes it, so the line never lies on the bottom rim.
    private func updateHeaderSeparatorFade() {
        let revealed = (panel.frame.height - theme.searchHeight) / max(1, theme.resultTopInset)
        let alpha = min(1, max(0, revealed))
        if headerSeparator.alphaValue != alpha { headerSeparator.alphaValue = alpha }
    }

    private func resizePanel(to height: CGFloat, display: Bool) {
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: height)
        let shouldAnimate = display && panel.isVisible && frame.size != panel.frame.size
            && max(0, cachedExpansionAnimationDuration) > 0
        if shouldAnimate {
            // Rows and text have already committed synchronously above this call. Only the
            // surface motion is deferred, so input and result delivery never wait for it.
            // Growth starts on the next main-loop turn; a shrink waits briefly so a newer
            // keystroke can keep the panel open instead of collapsing and regrowing it.
            let isShrinking = frame.height < panel.frame.height
            if isShrinking {
                // Keep the rows mounted and let the rising bottom edge clip them. Hiding the
                // viewport up front produced the "empty glass that collapses" flash.
                // Visibility settles when the motion ends.
                scrollView.isHidden = false
            } else {
                holdsRowsForCollapse = false
                if !rowsHeldForClip.isEmpty {
                    rowsHeldForClip = []
                    reloadResultsPreservingSelection(selectedResultID)
                }
                if presentsResultViewport {
                    setResultsViewportMotionHeight(
                        theme.resultsViewportHeight(resultCount: results.count)
                    )
                }
            }
            pendingExpansionTarget = frame
            scheduleExpansionFlush(after: isShrinking ? LauncherMotionMetrics.shrinkDelay : 0)
        } else {
            cancelPendingPanelMotion()
            releaseRowsHeldForClipping(clearResults: holdsRowsForCollapse)
            commitPanelFrame(frame, display: display)
        }
    }

    private func scheduleExpansionFlush(after delay: TimeInterval) {
        expansionFlush?.cancel()
        let flush = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushPendingExpansion() }
        }
        expansionFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: flush)
    }

    private func flushPendingExpansion() {
        expansionFlush = nil
        // Window Server owns the frame while the pointer drags the chrome; the drag's end
        // retargets from the dropped position.
        guard !isNativeWindowDragActive, let target = pendingExpansionTarget else { return }
        pendingExpansionTarget = nil
        stopResizeAnimation()
        let startHeight = panel.frame.height
        let targetHeight = target.height
        // `setFrame(_:display:animate: true)` runs a blocking animation that holds every
        // keystroke until it finishes. A nonblocking animation steps the same window-server
        // frame between events, and a newer target restarts from the interpolated height.
        let animation = LauncherPanelResizeAnimation(
            duration: cachedExpansionAnimationDuration,
            step: { [weak self] progress in
                guard let self else { return }
                let height = startHeight + (targetHeight - startHeight) * progress
                // AppKit widens a half-point window height to a whole point, while the
                // content keeps the requested height and drops half a point below the top.
                self.applyPanelGeometry(
                    LauncherPanelGeometry.resizing(
                        self.panel.frame,
                        toHeight: height.rounded()
                    ),
                    display: true
                )
            },
            completion: { [weak self] in
                guard let self else { return }
                self.resizeAnimation = nil
                self.finishPanelMotion()
            }
        )
        animation.frameRate = Float(panel.screen?.maximumFramesPerSecond ?? 60)
        resizeAnimation = animation
        animation.start()
    }

    private func stopResizeAnimation() {
        guard let animation = resizeAnimation else { return }
        resizeAnimation = nil
        animation.stop()
    }

    /// Reduce Motion (sampled through the controller's environment) collapses the motion to
    /// the instant commit; an injected duration overrides both for deterministic tests.
    private var effectiveExpansionAnimationDuration: TimeInterval {
        expansionAnimationDuration?()
            ?? (environmentProvider().reducesMotion
                ? 0
                : LauncherMotionMetrics.expansionAnimationDuration)
    }

    /// The instant commit used for first presentation, dismissal, accessibility fallbacks,
    /// and any nonanimated resize. Nothing in this transaction may animate.
    private func commitPanelFrame(_ frame: NSRect, display: Bool) {
        let shapeChanged = frame.size != panel.frame.size
        applyPanelGeometry(frame, display: display) {
            scrollView.alphaValue = 1
            scrollView.isHidden = !presentsResultViewport
        }
        if shapeChanged && panel.hasShadow { panel.invalidateShadow() }
    }

    /// One nonanimated geometry transaction, shared by the instant commit and every step of
    /// the height motion so the window, its full-bleed surfaces, and the rows never diverge.
    private func applyPanelGeometry(
        _ frame: NSRect,
        display: Bool,
        beforeDisplay: () -> Void = {}
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            // setFrame(display: true) draws immediately, before our glass layout finishes.
            // Commit the new geometry first; draw and refresh the native shadow afterward.
            if frame != panel.frame { panel.setFrame(frame, display: false, animate: false) }
            let contentFrame = NSRect(origin: .zero, size: panel.frame.size)
            retainedContentView?.frame = contentFrame
            // Autoresizing only fires when the superview frame actually changes. Force
            // every full-bleed surface to the committed bounds so window clip, frost, and
            // glass never diverge.
            if let host = retainedContentView {
                for surface in host.subviews where surface.translatesAutoresizingMaskIntoConstraints {
                    surface.frame = host.bounds
                }
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            updateHeaderSeparatorFade()
            beforeDisplay()
            if display && panel.isVisible { panel.displayIfNeeded() }
        }
    }

    /// Applies the post-motion state: exact committed geometry, settled result-viewport
    /// visibility, and a shadow that matches the final outline.
    private func finishPanelMotion() {
        releaseRowsHeldForClipping(clearResults: holdsRowsForCollapse)
        setResultsViewportMotionHeight(nil)
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: desiredPanelHeight)
        commitPanelFrame(frame, display: panel.isVisible)
        if panel.hasShadow { panel.invalidateShadow() }
    }

    /// Drops surplus rows once the window has finished clipping them. A full collapse also
    /// clears the list it was holding.
    private func releaseRowsHeldForClipping(clearResults: Bool) {
        let hadSurplus = !rowsHeldForClip.isEmpty
        let selectedID = selectedResultID
        holdsRowsForCollapse = false
        rowsHeldForClip = []
        guard clearResults || hadSurplus else { return }
        if clearResults {
            results = []
            confirmationEntryID = nil
            tableView.reloadData()
        } else {
            reloadResultsPreservingSelection(selectedID)
        }
        updateResultsGeometry()
    }

    /// Reloads the table without letting the accent selection drop out and return.
    private func reloadResultsPreservingSelection(_ entryID: String?) {
        let row = LauncherSelection.preferredRow(preservingEntryID: entryID, in: results)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            if let row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            tableView.reloadData()
            if let row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
            refreshSelectionAppearance()
        }
    }

    /// Drops any scheduled or in-flight transition, leaving the window frame where it is.
    /// Callers that need a specific frame commit it themselves.
    private func cancelPendingPanelMotion() {
        expansionFlush?.cancel()
        expansionFlush = nil
        pendingExpansionTarget = nil
        setResultsViewportMotionHeight(nil)
        stopResizeAnimation()
    }

    private func refreshSelectionAppearance() {
        guard tableView.numberOfColumns > 0 else { return }
        for row in 0..<results.count {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultRowView)?
                .setSelected(row == tableView.selectedRow)
        }
    }

    private func reloadVisibleIcon(for key: String) {
        let reloadsSettingsBadges = key == IconCache.systemSettingsBadgeIconKey
        let rows = IndexSet(results.indices.filter {
            results[$0].entry.iconKey == key
                || (reloadsSettingsBadges && results[$0].entry.kind == .systemSetting)
        })
        guard !rows.isEmpty else { return }
        for row in rows { _ = tableView(tableView, viewFor: tableView.tableColumns.first, row: row) }
        refreshSelectionAppearance()
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let height = max(theme.searchHeight, currentPanelHeight)
        let frame = LauncherPanelGeometry.positionedFrame(
            in: screen.visibleFrame,
            preferredWidth: theme.width,
            height: height,
            originX: theme.originX,
            originY: theme.originY
        )
        panel.setFrame(frame, display: false)
    }

    private func handlePotentialMove(with event: NSEvent) -> Bool {
        guard let content = panel.contentView else { return false }
        let hit = content.hitTest(event.locationInWindow)
        if let editor = searchField.currentEditor(),
           hit === editor || hit?.isDescendant(of: editor) == true {
            return false
        }
        guard LauncherPanelGeometry.isDraggableChrome(
            hitView: hit,
            searchField: searchField,
            resultsView: scrollView
        ) else { return false }
        beginNativeWindowDrag(with: event)
        return true
    }

    /// Hands a chrome mouse-down to Window Server. The app must not `setFrame` while the
    /// pointer is down; that redraws HUD glass on every dragged event and trails the cursor.
    /// `performDrag(with:)` returns immediately and may swallow mouse-up, so end-of-drag
    /// persistence is driven by monitors, `windowDidMove`, and a button-state poll.
    private func beginNativeWindowDrag(with event: NSEvent) {
        guard !isNativeWindowDragActive else { return }
        isNativeWindowDragActive = true
        stopResizeAnimation()
        installNativeDragEndObservers()
        panel.performDrag(with: event)
        if NSEvent.pressedMouseButtons & 1 == 0 {
            finishNativeWindowDrag()
        }
    }

    private func installNativeDragEndObservers() {
        removeNativeDragEndObservers()
        nativeDragLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                self?.finishNativeWindowDrag()
            }
            return event
        }
        nativeDragGlobalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.finishNativeWindowDrag()
            }
        }
        let poll = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.finishNativeWindowDragIfMouseIsUp()
            }
        }
        poll.tolerance = 0.004
        RunLoop.main.add(poll, forMode: .common)
        nativeDragEndPoll = poll
    }

    private func removeNativeDragEndObservers() {
        if let nativeDragLocalMouseUpMonitor {
            NSEvent.removeMonitor(nativeDragLocalMouseUpMonitor)
            self.nativeDragLocalMouseUpMonitor = nil
        }
        if let nativeDragGlobalMouseUpMonitor {
            NSEvent.removeMonitor(nativeDragGlobalMouseUpMonitor)
            self.nativeDragGlobalMouseUpMonitor = nil
        }
        nativeDragEndPoll?.invalidate()
        nativeDragEndPoll = nil
    }

    private func finishNativeWindowDragIfMouseIsUp() {
        guard isNativeWindowDragActive, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        finishNativeWindowDrag()
    }

    private func finishNativeWindowDrag() {
        guard isNativeWindowDragActive else { return }
        isNativeWindowDragActive = false
        removeNativeDragEndObservers()
        commitMove()
        if panel.isVisible { resizePanel(to: desiredPanelHeight, display: true) }
    }

    private func commitMove() {
        let screen = clampingScreen(for: panel.frame) ?? panel.screen
        guard let visibleFrame = screen?.visibleFrame else { return }
        let placement = LauncherPanelGeometry.committedPlacement(
            frame: panel.frame,
            visibleFrame: visibleFrame
        )
        if placement.frame != panel.frame {
            commitPanelFrame(placement.frame, display: panel.isVisible)
        }
        if var appearance = appliedAppearance {
            appearance.originX = Double(placement.originX)
            appearance.originY = Double(placement.originY)
            appliedAppearance = appearance
            theme = themeController.descriptor(for: appearance, environment: environmentProvider())
        }
        onOriginCommitted?(Double(placement.originX), Double(placement.originY))
    }

    private func clampingScreen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let matching = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
            return matching
        }
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }
    }
}

private extension NSRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
