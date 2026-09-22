@preconcurrency import AppKit
import BroccoliCore
import Foundation

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

    let bounds: NSRect
    var metrics: LauncherSearchMetrics = .spotlight

    var searchButtonRect: NSRect {
        NSRect(
            x: bounds.minX,
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
        LauncherSearchGeometry(bounds: rect, metrics: searchMetrics).searchButtonRect
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        LauncherSearchGeometry(bounds: rect, metrics: searchMetrics).searchTextRect
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        LauncherSearchGeometry(bounds: rect, metrics: searchMetrics).cancelButtonRect
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

final class LauncherNativeSearchField: NSSearchField {
    private let centeredPlaceholderView = LauncherSearchPlaceholderView(frame: .zero)
    private let inlineSuggestionView = LauncherSearchPlaceholderView(frame: .zero)
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

    override var searchButtonBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds, metrics: searchMetrics).searchButtonRect,
            options: .alignAllEdgesNearest
        )
    }

    override var searchTextBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds, metrics: searchMetrics).searchTextRect,
            options: .alignAllEdgesNearest
        )
    }

    override var cancelButtonBounds: NSRect {
        backingAlignedRect(
            LauncherSearchGeometry(bounds: bounds, metrics: searchMetrics).cancelButtonRect,
            options: .alignAllEdgesNearest
        )
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

/// The complete Liquid Glass launcher surface.
///
/// The launcher is one continuous HUD material that samples the desktop behind the window.
/// `NSGlassEffectView` was measured against this at both the collapsed capsule height and the
/// expanded launcher height: its lens is nearly blur-free at pill size, and layering a material
/// beneath it only removes the lens, because glass samples in-window content too. A single
/// behind-window material is what produces a readable backdrop at every height.
///
/// Do not layer-back that material to round it. A layer-backed visual-effect view drops
/// vibrancy, so placeholder text and the header rule composite as plain gray over wallpaper.
@MainActor
final class LauncherLiquidGlassSurfaceView: NSView {
    static let cornerRadius = LauncherLiquidGlassMetrics.cornerRadius
    static let collapsedHeight = LauncherLiquidGlassMetrics.searchHeight

    private let materialView = NSVisualEffectView()
    private var hostedContent: NSView?

    init(frame frameRect: NSRect = .zero, interactive: Bool = false) {
        super.init(frame: frameRect)
        // Keep this argument source-compatible with live and preview callers. The surface is
        // passive in both: it must never paint a local response lens around editable content.
        _ = interactive

        // Configure the persistent surface once. Resizing and appearance changes must not
        // select a different material, blending mode, or corner treatment. AppKit derives
        // Light and Dark from the inherited appearance and handles Reduce Transparency and
        // Increase Contrast itself. A stretchable mask rounds the capsule without
        // `wantsLayer`, which would flatten vibrancy for every descendant.
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.maskImage = Self.stretchingCornerMask(radius: Self.cornerRadius)
        addSubview(materialView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        materialView.frame = bounds
    }

    func setContentView(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        // Host content on the material itself so labels and the header rule stay in the
        // vibrancy hierarchy. Give it destination geometry before activating constraints:
        // a detached preview has no window display cycle to expand a zero-sized effect
        // view afterward, so it would otherwise settle at the search field's fitting height.
        materialView.frame = bounds
        view.frame = bounds
        view.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            view.topAnchor.constraint(equalTo: materialView.topAnchor),
            view.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),
        ])
    }

    /// Cap-inset mask that stretches to any panel size while keeping the shared corner radius.
    private static func stretchingCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let size = NSSize(width: edge, height: edge)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let layer = CALayer()
            layer.frame = rect
            layer.backgroundColor = NSColor.black.cgColor
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.render(in: context)
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let textGroupGuide = NSLayoutGuide()
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconDrawingWidthConstraint: NSLayoutConstraint!
    private var iconDrawingHeightConstraint: NSLayoutConstraint!
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
        case .application, .systemSetting:
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
        case .application, .systemSetting:
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
    private let modeBadge = NSTextField(labelWithString: "")
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
    private var defaultSearchLeadingConstraint: NSLayoutConstraint?
    private var modeSearchLeadingConstraint: NSLayoutConstraint?
    private var modeBadgeWidthConstraint: NSLayoutConstraint?
    private var currentMode: LauncherMode = .main
    private var presentationSessionActive = false
    /// Liquid Glass starts as one compact search capsule. Any useful match opens one stable
    /// result viewport so a single Finder/application result is never hidden in the header.
    private var liquidResultsExpanded = false
    private var arrowRepeatGate = LauncherArrowRepeatGate()
    /// The newest committed geometry whose motion has not started yet. Result changes coalesce
    /// here so a burst of keystrokes schedules one transition instead of one per key.
    private var pendingExpansionTarget: NSRect?
    private var expansionFlushScheduled = false
    private var expansionAnimationGeneration: UInt64 = 0
    private var expansionMotionInProgress = false
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
    /// True while a sanctioned height transition is scheduled, coalescing, or in flight.
    var isExpansionAnimationInFlight: Bool {
        expansionMotionInProgress || pendingExpansionTarget != nil
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
        modeBadge.effectiveAppearance.performAsCurrentDrawingAppearance {
            modeBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        }
        LauncherNativeSearchFieldStyle.apply(
            to: nativeSearchField,
            metrics: theme.searchMetrics,
            iconColor: theme.searchIconColor,
            placeholderColor: theme.searchPlaceholderColor
        )
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
        // Spotlight keeps its initial Liquid Glass presentation as a single search capsule.
        // Recent results remain available to the other designs and specialized modes, but the
        // main Liquid Glass launcher expands only after the user supplies a query.
        let suppressesEmptyMainResults = theme.design == .liquidGlass
            && currentMode == .main
            && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let query = searchField.stringValue
        let shouldResetScroll = query != lastAppliedQuery
        lastAppliedQuery = query
        // Search producers honor the bounded result-set cap. Clamp defensively here so a
        // streaming producer cannot grow without limit. Extra rows beyond the viewport stay
        // in the list and scroll.
        self.results = suppressesEmptyMainResults
            ? []
            : Array(listedResults.prefix(LauncherSearchLimits.resultSetCap))
        // Visible rows start their own interactive loads from `image(for:)` during the
        // reload below. Warming them again here only queued a second materialization of the
        // same artwork behind the first.
        updateInlineSuggestionPresentation()
        updateLiquidPresentationState()
        if !self.results.contains(where: { $0.entry.id == confirmationEntryID }) {
            confirmationEntryID = nil
        }
        tableView.reloadData()
        if shouldResetScroll {
            resetTableScrollPosition()
        }
        if inlineSuggestion != nil, selectedEntryID == nil {
            tableView.deselectAll(nil)
        } else if let preferredRow = LauncherSelection.preferredRow(
            preservingEntryID: selectedEntryID,
            in: self.results
        ) {
            tableView.selectRowIndexes(IndexSet(integer: preferredRow), byExtendingSelection: false)
            if !shouldResetScroll {
                scrollSelectedRowVisible()
            }
        } else {
            tableView.deselectAll(nil)
        }
        refreshSelectionAppearance()
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

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row), preparedResultRows.indices.contains(row) else {
            return nil
        }
        // Views are prepared up to the bounded result-set cap so scrolling beyond the
        // viewport never allocates row chrome on the first keystroke.
        let view = preparedResultRows[row]
        let result = results[row]
        view.configure(
            result: result,
            icon: iconCache.image(for: result.entry, context: iconContext),
            confirmation: confirmationEntryID == result.entry.id,
            row: row,
            selected: tableView.selectedRow == row,
            theme: theme,
            shortcutSlot: row - firstFullyVisibleResultRow()
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
        defaultSearchLeadingConstraint?.isActive = false
        modeSearchLeadingConstraint?.isActive = false
        nativeSearchField.removeFromSuperview()
        liquidGlassSurface.removeFromSuperview()
        modeBadge.removeFromSuperview()
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
            // The window shadow follows the composited window contents. Clip its outer
            // content boundary to the same geometry as the material surface, including while
            // the backdrop changes size; rectangular corner pixels must not reach WindowServer.
            host.wantsLayer = true
            host.layer?.cornerCurve = .continuous
            host.layer?.cornerRadius = theme.cornerRadius
            host.layer?.masksToBounds = true
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
            modeBadge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: theme.searchHorizontalInset),
            modeBadge.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),
            modeBadge.heightAnchor.constraint(equalToConstant: 26),
        ]
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
        modeBadge.effectiveAppearance.performAsCurrentDrawingAppearance {
            modeBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        }
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
            } else if let inlineSuggestion {
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

    private func updateModeChrome() {
        defaultSearchLeadingConstraint?.isActive = false
        modeSearchLeadingConstraint?.isActive = false

        let placeholder: String
        switch currentMode {
        case .main:
            modeBadge.isHidden = true
            defaultSearchLeadingConstraint?.isActive = true
            placeholder = "Search Broccoli"
        case .fileSearch:
            modeBadge.stringValue = "Files"
            modeBadgeWidthConstraint?.constant = 54
            modeBadge.isHidden = false
            modeSearchLeadingConstraint?.isActive = true
            placeholder = "Search names and paths"
        case .clipboard:
            modeBadge.stringValue = "Clipboard"
            modeBadgeWidthConstraint?.constant = 78
            modeBadge.isHidden = false
            modeSearchLeadingConstraint?.isActive = true
            placeholder = "Filter history"
        }
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
        let hasResults = presentsResultViewport
        let insets = theme.resultVerticalInsets(resultCount: hasResults ? results.count : 0)
        resultsTopConstraint?.constant = theme.searchHeight + insets.top
        resultsBottomConstraint?.constant = -insets.bottom
        scrollView.isHidden = !hasResults
        updateHeaderSeparatorVisibility()
    }

    private func updateHeaderSeparatorVisibility() {
        headerSeparator.isHidden = !theme.shouldShowHeaderSeparator(
            hasResults: presentsResultViewport,
            selectedRow: tableView.selectedRow
        )
    }

    private func resizePanel(to height: CGFloat, display: Bool) {
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: height)
        let shouldAnimate = display && panel.isVisible && frame.size != panel.frame.size
            && max(0, cachedExpansionAnimationDuration) > 0
        if shouldAnimate {
            // Rows and text have already committed synchronously above this call. Only the
            // surface motion is deferred, to the next main-loop turn, so input and result
            // delivery never wait for animation work.
            pendingExpansionTarget = frame
            scheduleExpansionFlush()
        } else {
            cancelPendingPanelMotion()
            commitPanelFrame(frame, display: display)
        }
    }

    private func scheduleExpansionFlush() {
        guard !expansionFlushScheduled else { return }
        expansionFlushScheduled = true
        expansionAnimationGeneration &+= 1
        let generation = expansionAnimationGeneration
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingExpansion(generation: generation)
            }
        }
    }

    private func flushPendingExpansion(generation: UInt64) {
        expansionFlushScheduled = false
        guard expansionAnimationGeneration == generation,
              let target = pendingExpansionTarget
        else { return }
        pendingExpansionTarget = nil
        expansionMotionInProgress = true
        if target.height < panel.frame.height {
            // While shrinking, keep the rows mounted and let the rising bottom edge clip
            // them. Hiding the viewport up front is what produced the "empty glass that
            // collapses" flash. Visibility settles when the motion ends.
            scrollView.isHidden = false
        }
        expansionAnimationGeneration &+= 1
        let motionGeneration = expansionAnimationGeneration
        // The native window-server resize lets the material surface track every step, and a
        // newer resize restarts from the interpolated frame by itself. CA-driven frame
        // animation instead desynchronizes the surface from its content, which read as
        // doubled text and a collapsing ghost panel.
        panel.setFrame(target, display: true, animate: true)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LauncherMotionMetrics.nativeResizeSettlement,
            execute: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self,
                          self.expansionAnimationGeneration == motionGeneration
                    else { return }
                    self.expansionMotionInProgress = false
                    self.finishPanelMotion()
                }
            }
        )
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            // setFrame(display: true) draws immediately, before our glass layout finishes.
            // Commit the new geometry first; draw and refresh the native shadow afterward.
            if frame != panel.frame { panel.setFrame(frame, display: false, animate: false) }
            let contentFrame = NSRect(origin: .zero, size: frame.size)
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
            scrollView.alphaValue = 1
            scrollView.isHidden = !presentsResultViewport
            if display && panel.isVisible { panel.displayIfNeeded() }
            if shapeChanged && panel.hasShadow { panel.invalidateShadow() }
        }
    }

    /// Applies the post-motion state: exact committed geometry, settled result-viewport
    /// visibility, and a shadow that matches the final outline.
    private func finishPanelMotion() {
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: desiredPanelHeight)
        commitPanelFrame(frame, display: panel.isVisible)
    }

    /// Drops any not-yet-started transition and settles motion state without touching the
    /// window frame. Callers that need a specific frame commit it themselves.
    private func cancelPendingPanelMotion() {
        expansionAnimationGeneration &+= 1
        pendingExpansionTarget = nil
        expansionMotionInProgress = false
    }

    private func refreshSelectionAppearance() {
        guard tableView.numberOfColumns > 0 else { return }
        for row in 0..<results.count {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultRowView)?
                .setSelected(row == tableView.selectedRow)
        }
    }

    private func reloadVisibleIcon(for key: String) {
        let rows = IndexSet(results.indices.filter { results[$0].entry.iconKey == key })
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
