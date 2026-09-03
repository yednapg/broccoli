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

    static func addingCompositingOutset(_ outset: CGFloat, to visualFrame: NSRect) -> NSRect {
        visualFrame.insetBy(dx: -max(0, outset), dy: -max(0, outset))
    }

    static func removingCompositingOutset(_ outset: CGFloat, from outerFrame: NSRect) -> NSRect {
        outerFrame.insetBy(dx: max(0, outset), dy: max(0, outset))
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

/// Draws the Figma header rule as actual one-point ink. Liquid Glass uses the source file's
/// tiny 0.288° rise; Minimal remains horizontal. A custom view avoids rotating an entire
/// layer, which otherwise softens the rule and makes its end points asymmetric on Retina.
@MainActor
final class LauncherHeaderSeparatorView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    var lineThickness: CGFloat = 1 { didSet { needsDisplay = true } }
    var angleDegrees: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

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
        set { textStorage?.setAttributedString(newValue) }
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
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = true
    }

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

    /// Render a semantic color into the symbol pixels instead of leaving the image as a
    /// template. AppKit otherwise re-vibrantizes the search-button template when the native
    /// glass changes size, which makes the magnifier flash brighter while the text stays
    /// steady. The resolved pixels retain the correct light/dark color without participating
    /// in that independent vibrancy transition.
    private static func stableSymbol(
        named name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        size: CGFloat,
        color: NSColor,
        appearance: NSAppearance,
        drawingScale: CGFloat = 1,
        drawingVerticalScale: CGFloat = 1
    ) -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) else {
            return nil
        }
        var resolvedColor = color
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        }
        let outputSize = NSSize(width: size, height: size)
        let image = NSImage(size: outputSize, flipped: false) { rect in
            resolvedColor.setFill()
            rect.fill()
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
            symbol.draw(
                in: drawingRect,
                from: .zero,
                operation: .destinationIn,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
        image.isTemplate = false
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
        iconColor: NSColor
    ) {
        let cell = LauncherNativeSearchFieldCell(textCell: "")
        cell.searchMetrics = metrics
        searchField.cell = cell
        (searchField as? LauncherNativeSearchField)?.searchMetrics = metrics
        let defaultPlaceholder = placeholder(
            "Search",
            metrics: metrics,
            color: .placeholderTextColor
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
        if let magnifier = stableSymbol(
            named: "magnifyingglass",
            pointSize: metrics.symbolPointSize,
            weight: .regular,
            size: metrics.symbolSize,
            color: iconColor,
            appearance: searchField.effectiveAppearance,
            drawingScale: metrics.symbolDrawingScale,
            drawingVerticalScale: metrics.symbolDrawingVerticalScale
        ) {
            cell.searchButtonCell?.image = magnifier
            cell.searchButtonCell?.imageScaling = .scaleProportionallyUpOrDown
            cell.searchButtonCell?.imageDimsWhenDisabled = false
            cell.searchButtonCell?.highlightsBy = []
            cell.searchButtonCell?.showsStateBy = []
        }
        if let cancel = stableSymbol(
            named: "xmark.circle.fill",
            pointSize: 15,
            weight: .regular,
            size: metrics.cancelSize,
            color: .secondaryLabelColor,
            appearance: searchField.effectiveAppearance
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
/// Liquid Glass is a single functional surface in Spotlight. Embedding the launcher content
/// through `contentView` lets AppKit coordinate legibility and sampling while the search field
/// remains fully interactive. The glass itself stays passive so AppKit cannot paint a temporary
/// rectangular response lens around a click inside the capsule.
@MainActor
final class LauncherLiquidGlassSurfaceView: NSView {
    static let expandedCornerRadius = LauncherLiquidGlassMetrics.expandedCornerRadius
    static let collapsedHeight = LauncherLiquidGlassMetrics.searchHeight

    private let contentHost = NSView()
    private var hostedContent: NSView?
    private var nativeGlass: NSView?
    private var fallbackEffect: NSVisualEffectView?
    private var glassTintColor: NSColor?

    init(frame frameRect: NSRect = .zero, interactive: Bool = false) {
        super.init(frame: frameRect)
        // Keep this argument source-compatible with live and preview callers. It must not
        // enable NSGlassEffectView's local click-response lens around editable content.
        _ = interactive
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.width, .height]

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = Self.collapsedHeight / 2
            // Regular glass bounds the desktop's influence and supplies AppKit's standard
            // legibility treatment. Clear glass reacts too strongly to bright or colorful
            // wallpaper for a launcher whose primary content is editable text.
            glass.style = .regular
            glass.tintColor = nil
            if #available(macOS 27, *) {
                glass.effectIsInteractive = false
            }
            glass.contentView = contentHost
            addSubview(glass)
            nativeGlass = glass
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
        let isExpanded = bounds.height > Self.collapsedHeight + 0.5
        if #available(macOS 26, *), let glass = nativeGlass as? NSGlassEffectView {
            glass.frame = bounds
            glass.cornerRadius = !isExpanded
                ? bounds.height / 2
                : Self.expandedCornerRadius
            glass.style = .regular
            glass.tintColor = glassTintColor
        }
        let fallbackRadius = !isExpanded
            ? bounds.height / 2
            : Self.expandedCornerRadius
        fallbackEffect?.wantsLayer = true
        fallbackEffect?.layer?.cornerRadius = fallbackRadius
        fallbackEffect?.layer?.cornerCurve = .continuous
        fallbackEffect?.layer?.masksToBounds = true
    }

    func configure(isDark: Bool, tintColor: NSColor?) {
        // Retain the parameter while live and preview callers share this surface API. Text and
        // tint still follow appearance without changing the regular material variant.
        _ = isDark
        glassTintColor = tintColor
        needsLayout = true
    }

    func setContentView(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        // NSGlassEffectView owns a private content-view layout pass. Give that hierarchy its
        // destination geometry before activating descendant constraints; installing into the
        // initial zero-sized lens makes AppKit briefly recover by breaking a private glass
        // constraint, even though the next layout pass reaches the expected frame.
        contentHost.frame = bounds
        view.frame = contentHost.bounds
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
    static let statusIconSize = LauncherLiquidGlassMetrics.statusIconSize

    private let iconSlot = NSLayoutGuide()
    private let resultIcon = NSImageView()
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
    private var usesAdaptiveSelectionText = false
    private var usesFullWidthSelectionBackground = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
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
        theme: LauncherThemeDescriptor
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
        let configuredIcon = sourceIcon.isTemplate
            ? (sourceIcon.withSymbolConfiguration(.init(
                pointSize: templatePointSize,
                weight: templateWeight
            )) ?? sourceIcon)
            : sourceIcon
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
        let showsShortcut = theme.showsShortcuts && result.entry.kind != .status
        subtitleLabel.isHidden = !showsSubtitle
        shortcutLabel.isHidden = !showsShortcut
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
        titleToShortcutConstraint.isActive = showsShortcut
        subtitleToShortcutConstraint.isActive = showsShortcut
        titleToEdgeConstraint.isActive = !showsShortcut
        subtitleToEdgeConstraint.isActive = !showsShortcut
        shortcutLabel.stringValue = LauncherNumericShortcut.label(forRow: row)
        selectionColor = theme.selectionColor
        usesAdaptiveSelectionText = theme.design == .liquidGlass
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

    func setSelected(_ selected: Bool) {
        self.selected = selected
        updateSelectionBackground()
        updateColors()
    }

    private func updateSelectionBackground() {
        let color = selected ? selectionColor.cgColor : NSColor.clear.cgColor
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
    private static let panelWidth = LauncherMinimalMetrics.width
    private static let searchHeight = LauncherMinimalMetrics.searchHeight
    private static let maximumPreparedResultRows = 10
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
    private var theme: LauncherThemeDescriptor
    private var retainedContentView: NSView?
    private var results: [RankedResult] = []
    private var inlineSuggestion: RankedResult?
    private var confirmationEntryID: String?
    private var isProgrammaticallyHiding = false
    private var pendingAppearance: LauncherAppearancePreferences?
    private var appliedAppearance: LauncherAppearancePreferences?
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
            styleMask: [.borderless, .nonactivatingPanel],
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
    var searchPlaceholder: String? { nativeSearchField.centeredPlaceholderAttributedString?.string }
    var usesNativeSearchField: Bool { searchField is LauncherNativeSearchField }
    var resultsAccessibilityLabel: String? { tableView.accessibilityLabel() }
    var isContentViewAttached: Bool {
        panel.contentView != nil && panel.contentView === retainedContentView
    }
    var isSearchSurfaceWindowBacked: Bool { liquidGlassSurface.window === panel }
    var isResultViewportVisible: Bool { !scrollView.isHidden }
    var listedResultIDs: [String] { results.map(\.entry.id) }
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
        max(0, panel.frame.height - surfaceCompositingOutset * 2)
    }

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
        let oldVisualFrame = LauncherPanelGeometry.removingCompositingOutset(
            surfaceCompositingOutset,
            from: panel.frame
        )
        pendingAppearance = nil
        appliedAppearance = preferences
        theme = themeController.descriptor(for: preferences)
        panel.appearance = theme.appearance
        panel.hasShadow = theme.hasShadow
        tableView.rowHeight = theme.rowHeight
        // Resize both axes before installing the constrained content tree. A controller is
        // born at Minimal's width; installing Liquid Glass inside that stale frame makes
        // AppKit break the content-width constraint while the hidden launcher is prepared.
        // Detach that old constrained tree first; appearance changes are queued while visible,
        // so this replacement always occurs while the panel is safely ordered out.
        panel.contentView = nil
        retainedContentView = nil
        let height = desiredPanelHeight(for: results.count)
        let preparedVisualFrame = NSRect(
            x: oldVisualFrame.midX - theme.width / 2,
            y: oldVisualFrame.maxY - height,
            width: theme.width,
            height: height
        )
        let preparedFrame = LauncherPanelGeometry.addingCompositingOutset(
            surfaceCompositingOutset,
            to: preparedVisualFrame
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
        inlineSuggestion = nil
        updateInlineSuggestionPresentation()
        tableView.reloadData()
        resetTableScrollPosition()
        updateResultsGeometry()
        resizePanel(to: desiredPanelHeight(for: 0), display: false)
        confirmationEntryID = nil
        onQueryChanged?("")
        position(on: screen ?? NSScreen.main ?? NSScreen.screens.first)
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
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
        // Search producers already honor the configured limit. Clamp defensively here as
        // well so a malformed or streaming producer can never create a scrollable viewport.
        self.results = suppressesEmptyMainResults
            ? []
            : Array(listedResults.prefix(theme.visibleResultCount))
        updateInlineSuggestionPresentation()
        updateLiquidPresentationState()
        if !self.results.contains(where: { $0.entry.id == confirmationEntryID }) {
            confirmationEntryID = nil
        }
        resetTableScrollPosition()
        tableView.reloadData()
        if inlineSuggestion != nil, selectedEntryID == nil {
            tableView.deselectAll(nil)
            resetTableScrollPosition()
        } else if let preferredRow = LauncherSelection.preferredRow(
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
        guard !isProgrammaticallyHiding else { return }
        // A click in another application already chose the next owner of focus. Hide the
        // launcher without reactivating the application that preceded Command-Space.
        dismiss(notify: false)
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
        panel.hasShadow = false
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
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.delegate = self
        panel.onCommand = { [weak self] command in self?.handle(command) }
    }

    private func configureContent() {
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

        let surfaceFrame = host.bounds.insetBy(
            dx: surfaceCompositingOutset,
            dy: surfaceCompositingOutset
        )
        let surface: NSView
        switch theme.surface {
        case .glass:
            if #available(macOS 26, *) {
                liquidGlassSurface.frame = surfaceFrame
                liquidGlassSurface.configure(
                    isDark: theme.isDark,
                    tintColor: theme.glassTintColor
                )
                liquidGlassSurface.layoutSubtreeIfNeeded()
                liquidGlassSurface.setContentView(content)
                surface = liquidGlassSurface
            } else {
                let fallback = NSView()
                install(content, in: fallback)
                surface = fallback
            }
        case .ultraThick:
            let material = LauncherMinimalMaterialSurfaceView(
                frame: host.bounds,
                isDark: theme.isDark
            )
            material.setContentView(content)
            surface = material
        case .vibrancy:
            let effect = NSVisualEffectView()
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.material = .underWindowBackground
            install(content, in: effect)
            surface = effect
        case .opaque:
            let backdrop = NSView()
            install(content, in: backdrop)
            surface = backdrop
        }
        surface.frame = surfaceFrame
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        if theme.surface != .glass, theme.surface != .ultraThick {
            surface.wantsLayer = true
            surface.layer?.backgroundColor = theme.surface == .opaque
                ? theme.backgroundColor.cgColor
                : nil
            surface.layer?.cornerRadius = theme.surfaceCornerRadius(
                panelHeight: host.bounds.height
            )
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
            iconColor: theme.searchIconColor
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
            searchChrome.heightAnchor.constraint(
                equalToConstant: theme.searchHeight - theme.searchControlVerticalInset * 2
            ),
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
        NSLayoutConstraint.activate(constraints)
        updateModeChrome()
        updateInlineSuggestionPresentation()
        tableView.rowHeight = theme.rowHeight
        tableView.reloadData()
        resetTableScrollPosition()
        refreshSelectionAppearance()
        updateHeaderSeparatorVisibility()
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
        case .executeIndex(let row):
            guard results.indices.contains(row), results[row].entry.kind != .status else { return }
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
                color: theme.searchTextColor
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
            color: theme.searchTextColor.withAlphaComponent(0.58),
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
        resizePanel(to: desiredPanelHeight(for: results.count), display: true)
        scrollView.alphaValue = 1
    }

    private func desiredPanelHeight(for resultCount: Int) -> CGFloat {
        if theme.design == .liquidGlass,
           currentMode == .main,
           !presentsResultViewport {
            return theme.searchHeight
        }
        return theme.panelHeight(resultCount: resultCount)
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

    private func updateResultsGeometry() {
        let hasResults = presentsResultViewport
        resultsTopConstraint?.constant = theme.searchHeight
            + (hasResults ? theme.resultTopInset : 0)
        resultsBottomConstraint?.constant = hasResults ? -theme.resultBottomInset : 0
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
        let outerHeight = height + surfaceCompositingOutset * 2
        let frame = LauncherPanelGeometry.resizing(panel.frame, toHeight: outerHeight)
        // Result updates happen on the typing path. Resizing synchronously prevents AppKit
        // from exposing intermediate glass thickness, shadow, and sampling states.
        panel.setFrame(frame, display: display, animate: false)
        // Keep the frame-based window root synchronized with the borderless panel. This also
        // commits the destination glass and row geometry as one update, before either the
        // hidden panel is ordered front or a visible result-count change is displayed.
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
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let height = max(theme.searchHeight, currentPanelHeight)
        let visualFrame = LauncherPanelGeometry.positionedFrame(
            in: screen.visibleFrame,
            preferredWidth: theme.width,
            height: height,
            verticalPosition: theme.verticalPosition
        )
        let frame = LauncherPanelGeometry.addingCompositingOutset(
            surfaceCompositingOutset,
            to: visualFrame
        )
        panel.setFrame(frame, display: false)
    }

    private var surfaceCompositingOutset: CGFloat {
        guard theme.design == .liquidGlass, theme.surface == .glass else { return 0 }
        return LauncherLiquidGlassMetrics.liveCompositingOutset
    }

}
