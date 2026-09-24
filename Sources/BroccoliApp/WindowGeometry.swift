import BroccoliCore
import CoreGraphics

extension WindowAction {
    /// Layouts that tile the display, so neighboring windows get the window gap between them.
    var isTiledLayout: Bool {
        switch group {
        case .halvesAndQuarters, .thirds: true
        default: false
        }
    }
}

/// Frames are in Accessibility coordinates: the origin is the top-left corner of the primary
/// display and y grows downward, so `screen.minY` is the top of the usable area.
enum WindowGeometry {
    /// A window closer than this to a screen edge is treated as docked to it. Grid-snapping
    /// applications such as Terminal leave a few points between a snapped window and the edge.
    static let edgeTolerance: CGFloat = 8
    /// Repeated half and quarter presses step through these widths (or heights).
    /// Repeated presses of the same half or quarter: half, then a third, then two thirds.
    static let cycleFractions: [CGFloat] = [1.0 / 2.0, 1.0 / 3.0, 2.0 / 3.0]

    /// `cycleFraction` replaces the ½ share of a half or quarter when the user has chosen
    /// Cycle Sizes for repeated presses.
    static func frame(
        for action: WindowAction,
        window: CGRect,
        screen: CGRect,
        options: WindowLayoutOptions = .standard,
        cycleFraction: CGFloat? = nil
    ) -> CGRect {
        let bounds = layoutBounds(for: action, screen: screen, options: options)
        let result = rawFrame(
            for: action,
            window: window,
            screen: bounds,
            options: options,
            cycleFraction: cycleFraction ?? 0.5
        )
        guard action.isTiledLayout, options.windowGap > 0 else { return result }
        return insetInterior(result, within: bounds, by: options.windowGap / 2)
    }

    /// The area a layout may use after the screen-edge gap. Almost Maximize and Center keep
    /// using the full area because they already leave a margin.
    static func layoutBounds(for action: WindowAction, screen: CGRect, options: WindowLayoutOptions) -> CGRect {
        guard options.screenEdgeGap > 0 else { return screen }
        switch action {
        case .minimized, .center:
            return screen
        default:
            return inset(screen, by: options.screenEdgeGap)
        }
    }

    static func inset(_ screen: CGRect, by gap: CGFloat) -> CGRect {
        guard gap > 0, screen.width > gap * 4, screen.height > gap * 4 else { return screen }
        return screen.insetBy(dx: gap, dy: gap)
    }

    /// Insets every edge that does not lie on `bounds`, so neighboring tiles end up `2 × by`
    /// apart while tiles stay flush with the gapped screen edge.
    static func insetInterior(_ frame: CGRect, within bounds: CGRect, by amount: CGFloat) -> CGRect {
        var minX = frame.minX, minY = frame.minY, maxX = frame.maxX, maxY = frame.maxY
        if abs(minX - bounds.minX) > 0.5 { minX += amount }
        if abs(maxX - bounds.maxX) > 0.5 { maxX -= amount }
        if abs(minY - bounds.minY) > 0.5 { minY += amount }
        if abs(maxY - bounds.maxY) > 0.5 { maxY -= amount }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private static func rawFrame(
        for action: WindowAction,
        window: CGRect,
        screen: CGRect,
        options: WindowLayoutOptions,
        cycleFraction share: CGFloat
    ) -> CGRect {
        let portrait = screen.height > screen.width
        switch action {
        case .leftHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width * share, height: screen.height)
        case .rightHalf:
            let width = screen.width * share
            return CGRect(x: screen.maxX - width, y: screen.minY, width: width, height: screen.height)
        case .topHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height * share)
        case .bottomHalf:
            let height = screen.height * share
            return CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        case .topLeftQuarter:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width * share, height: screen.height / 2)
        case .topRightQuarter:
            let width = screen.width * share
            return CGRect(x: screen.maxX - width, y: screen.minY, width: width, height: screen.height / 2)
        case .bottomLeftQuarter:
            return CGRect(x: screen.minX, y: screen.midY, width: screen.width * share, height: screen.height / 2)
        case .bottomRightQuarter:
            let width = screen.width * share
            return CGRect(x: screen.maxX - width, y: screen.midY, width: width, height: screen.height / 2)
        case .firstThird:
            return band(index: 0, span: 1, of: 3, in: screen, portrait: portrait)
        case .lastThird:
            return band(index: 2, span: 1, of: 3, in: screen, portrait: portrait)
        case .maximize:
            return screen
        case .minimized:
            // Almost Maximize: a centered window that keeps a desktop margin on every edge
            // while remaining large enough for productive work.
            let fraction = min(1, max(0.1, options.almostMaximizeFraction))
            let width = screen.width * fraction
            let height = screen.height * fraction
            return CGRect(
                x: screen.midX - width / 2,
                y: screen.midY - height / 2,
                width: width,
                height: height
            )
        case .maximizeHeight:
            let horizontal = clamped(Span(window, .horizontal), within: Span(screen, .horizontal))
            return rect(horizontal: horizontal, vertical: Span(screen, .vertical))
        case .maximizeWidth:
            let vertical = clamped(Span(window, .vertical), within: Span(screen, .vertical))
            return rect(horizontal: Span(screen, .horizontal), vertical: vertical)
        case .center:
            let width = min(window.width, screen.width)
            let height = min(window.height, screen.height)
            return CGRect(
                x: screen.midX - width / 2,
                y: screen.midY - height / 2,
                width: width,
                height: height
            )
        case .makeLarger:
            return resized(window, in: screen, horizontal: .grow, vertical: .grow, options: options)
        case .makeSmaller:
            // A window spanning the full height but not the full width is a column such as a
            // half or a third. Keep it a column and narrow it, as Rectangle does. A maximized
            // window shrinks on both axes.
            let horizontal = Span(window, .horizontal)
            let vertical = Span(window, .vertical)
            let isColumn = vertical.touchesBothEdges(of: Span(screen, .vertical))
                && !horizontal.touchesBothEdges(of: Span(screen, .horizontal))
            return resized(
                window,
                in: screen,
                horizontal: .shrink,
                vertical: isColumn ? .keep : .shrink,
                options: options
            )
        case .nextDisplay, .previousDisplay, .restore, .tileAll, .cascadeAll,
             .rotateLayout, .retileWindows, .toggleFloating:
            return window
        }
    }

    // MARK: - Custom frames

    static func frame(
        for spec: WindowFrameSpec,
        window: CGRect,
        screen: CGRect,
        options: WindowLayoutOptions = .standard
    ) -> CGRect {
        let bounds = spec.usesGaps ? inset(screen, by: options.screenEdgeGap) : screen
        func length(_ dimension: WindowDimension?, current: CGFloat, total: CGFloat) -> CGFloat {
            switch dimension?.sanitized {
            case nil: min(current, total)
            case .points(let value): min(CGFloat(value), total)
            case .percent(let value): total * CGFloat(value) / 100
            }
        }
        let width = length(spec.width, current: window.width, total: bounds.width)
        let height = length(spec.height, current: window.height, total: bounds.height)
        let origin: CGPoint
        switch spec.placement {
        case .anchor(let anchor):
            origin = CGPoint(
                x: bounds.minX + (bounds.width - width) * anchor.horizontalFraction,
                y: bounds.minY + (bounds.height - height) * anchor.verticalFraction
            )
        case .keepOrigin:
            origin = window.origin
        case .offset(let x, let y):
            origin = CGPoint(x: bounds.minX + CGFloat(x), y: bounds.minY + CGFloat(y))
        }
        return rect(
            horizontal: clamped(Span(start: origin.x, length: width), within: Span(bounds, .horizontal)),
            vertical: clamped(Span(start: origin.y, length: height), within: Span(bounds, .vertical))
        )
    }

    /// Places a workspace entry saved as fractions of a display's usable area.
    static func frame(for entry: WindowWorkspace.Entry, screen: CGRect) -> CGRect {
        CGRect(
            x: screen.minX + screen.width * CGFloat(entry.x),
            y: screen.minY + screen.height * CGFloat(entry.y),
            width: screen.width * CGFloat(entry.width),
            height: screen.height * CGFloat(entry.height)
        )
    }

    static func workspaceEntry(
        bundleIdentifier: String,
        frame: CGRect,
        screen: CGRect,
        displayIndex: Int
    ) -> WindowWorkspace.Entry {
        var entry = WindowWorkspace.Entry(
            bundleIdentifier: bundleIdentifier,
            displayIndex: displayIndex,
            x: Double((frame.minX - screen.minX) / max(1, screen.width)),
            y: Double((frame.minY - screen.minY) / max(1, screen.height)),
            width: Double(frame.width / max(1, screen.width)),
            height: Double(frame.height / max(1, screen.height))
        )
        entry.sanitize()
        return entry
    }

    // MARK: - Several windows

    /// A balanced grid with no empty cells: the last row's windows share its full width.
    static func gridFrames(count: Int, in bounds: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let rowHeight = bounds.height / CGFloat(rows)
        var frames: [CGRect] = []
        var remaining = count
        for row in 0..<rows {
            let cellsInRow = row == rows - 1 ? remaining : columns
            let cellWidth = bounds.width / CGFloat(cellsInRow)
            for column in 0..<cellsInRow {
                frames.append(CGRect(
                    x: bounds.minX + cellWidth * CGFloat(column),
                    y: bounds.minY + rowHeight * CGFloat(row),
                    width: cellWidth,
                    height: rowHeight
                ))
            }
            remaining -= cellsInRow
        }
        return gap > 0 ? frames.map { insetInterior($0, within: bounds, by: gap / 2) } : frames
    }

    /// Back-to-front cascade: each window is offset from the previous one and sized so the
    /// whole stack fits on the display.
    static func cascadeFrames(sizes: [CGSize], in bounds: CGRect, offset: CGFloat = 30) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let spread = offset * CGFloat(sizes.count - 1)
        let maximumWidth = max(bounds.width * 0.4, bounds.width - spread)
        let maximumHeight = max(bounds.height * 0.4, bounds.height - spread)
        return sizes.enumerated().map { index, size in
            let width = min(size.width, maximumWidth)
            let height = min(size.height, maximumHeight)
            let step = offset * CGFloat(index)
            return rect(
                horizontal: clamped(Span(start: bounds.minX + step, length: width), within: Span(bounds, .horizontal)),
                vertical: clamped(Span(start: bounds.minY + step, length: height), within: Span(bounds, .vertical))
            )
        }
    }

    /// Rebalances every window whenever one opens or closes.
    ///
    /// Two windows split the display in half. Three keep the first at half and stack the
    /// other two in the remaining half. Four or more divide the whole display evenly, so a
    /// fourth window becomes four quarters rather than a slice of the last cell.
    static func tiledFrames(count: Int, in bounds: CGRect, gap: CGFloat, startsSideBySide: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let frames = count == 3
            ? masterAndStackFrames(in: bounds, sideBySide: startsSideBySide)
            : balancedGridFrames(count: count, in: bounds, wide: startsSideBySide)
        return gap > 0 ? frames.map { insetInterior($0, within: bounds, by: gap / 2) } : frames
    }

    /// The first window fills one half. The other two share the remaining half.
    private static func masterAndStackFrames(in bounds: CGRect, sideBySide: Bool) -> [CGRect] {
        if sideBySide {
            let width = bounds.width / 2
            let height = bounds.height / 2
            return [
                CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
                CGRect(x: bounds.minX + width, y: bounds.minY, width: width, height: height),
                CGRect(x: bounds.minX + width, y: bounds.minY + height, width: width, height: height),
            ]
        }
        let height = bounds.height / 2
        let width = bounds.width / 2
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height),
            CGRect(x: bounds.minX, y: bounds.minY + height, width: width, height: height),
            CGRect(x: bounds.minX + width, y: bounds.minY + height, width: width, height: height),
        ]
    }

    /// Rows and columns that together cover the whole display. The last row's windows share
    /// its full width, so no cell is left over from an earlier split.
    private static func balancedGridFrames(count: Int, in bounds: CGRect, wide: Bool) -> [CGRect] {
        var columns = max(1, Int(ceil(sqrt(Double(count)))))
        var rows = Int(ceil(Double(count) / Double(columns)))
        if !wide, rows != columns {
            swap(&columns, &rows)
            if columns * rows < count { rows += 1 }
        }
        var frames: [CGRect] = []
        var remaining = count
        let rowHeight = bounds.height / CGFloat(rows)
        for row in 0..<rows {
            let cellsInRow = row == rows - 1
                ? remaining
                : Int(ceil(Double(remaining) / Double(rows - row)))
            let cellWidth = bounds.width / CGFloat(cellsInRow)
            for column in 0..<cellsInRow {
                frames.append(CGRect(
                    x: bounds.minX + cellWidth * CGFloat(column),
                    y: bounds.minY + rowHeight * CGFloat(row),
                    width: cellWidth,
                    height: rowHeight
                ))
            }
            remaining -= cellsInRow
        }
        return frames
    }

    static func movedFrame(window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let widthRatio = source.width > 0 ? window.width / source.width : 1
        let heightRatio = source.height > 0 ? window.height / source.height : 1
        let xRatio = source.width > window.width
            ? (window.minX - source.minX) / (source.width - window.width)
            : 0.5
        let yRatio = source.height > window.height
            ? (window.minY - source.minY) / (source.height - window.height)
            : 0.5
        let width = min(destination.width, destination.width * widthRatio)
        let height = min(destination.height, destination.height * heightRatio)
        return CGRect(
            x: destination.minX + max(0, destination.width - width) * min(1, max(0, xRatio)),
            y: destination.minY + max(0, destination.height - height) * min(1, max(0, yRatio)),
            width: width,
            height: height
        )
    }

    // MARK: - Grid layouts

    /// Columns on a landscape display and rows on a portrait one, so “first” is the left
    /// band or the top band respectively.
    private static func band(index: Int, span: Int, of count: Int, in screen: CGRect, portrait: Bool) -> CGRect {
        if portrait {
            let unit = screen.height / CGFloat(count)
            return CGRect(
                x: screen.minX,
                y: screen.minY + unit * CGFloat(index),
                width: screen.width,
                height: unit * CGFloat(span)
            )
        }
        let unit = screen.width / CGFloat(count)
        return CGRect(
            x: screen.minX + unit * CGFloat(index),
            y: screen.minY,
            width: unit * CGFloat(span),
            height: screen.height
        )
    }

    // MARK: - One-axis spans

    enum Axis { case horizontal, vertical }

    struct Span: Equatable {
        var start: CGFloat
        var length: CGFloat
        var end: CGFloat { start + length }

        init(start: CGFloat, length: CGFloat) {
            self.start = start
            self.length = length
        }

        init(_ rect: CGRect, _ axis: Axis) {
            switch axis {
            case .horizontal: self.init(start: rect.minX, length: rect.width)
            case .vertical: self.init(start: rect.minY, length: rect.height)
            }
        }

        func touchesLeadingEdge(of screen: Span) -> Bool {
            abs(start - screen.start) <= WindowGeometry.edgeTolerance
        }

        func touchesTrailingEdge(of screen: Span) -> Bool {
            abs(end - screen.end) <= WindowGeometry.edgeTolerance
        }

        func touchesBothEdges(of screen: Span) -> Bool {
            touchesLeadingEdge(of: screen) && touchesTrailingEdge(of: screen)
        }
    }

    private static func rect(horizontal: Span, vertical: Span) -> CGRect {
        CGRect(x: horizontal.start, y: vertical.start, width: horizontal.length, height: vertical.length)
    }

    /// Keeps a span's length (capped at the screen) and slides it fully onto the screen.
    static func clamped(_ span: Span, within screen: Span) -> Span {
        let length = min(span.length, screen.length)
        let start = min(max(span.start, screen.start), screen.end - length)
        return Span(start: start, length: length)
    }

    // MARK: - Resize

    enum Resize { case grow, shrink, keep }

    private static func resized(
        _ window: CGRect,
        in screen: CGRect,
        horizontal: Resize,
        vertical: Resize,
        options: WindowLayoutOptions
    ) -> CGRect {
        rect(
            horizontal: resizedSpan(
                Span(window, .horizontal),
                in: Span(screen, .horizontal),
                resize: horizontal,
                options: options
            ),
            vertical: resizedSpan(
                Span(window, .vertical),
                in: Span(screen, .vertical),
                resize: vertical,
                options: options
            )
        )
    }

    /// Resizes one axis while keeping any edge that is docked to the screen in place, so a
    /// left-half window grows to the right. A window docked to neither edge changes evenly on
    /// both sides. The result stays on the screen.
    static func resizedSpan(
        _ span: Span,
        in screen: Span,
        resize: Resize,
        options: WindowLayoutOptions
    ) -> Span {
        let length: CGFloat
        switch resize {
        case .keep:
            return span
        case .grow:
            guard span.length < screen.length else { return span }
            if span.touchesBothEdges(of: screen) { return span }
            length = min(span.length + options.resizeStep, screen.length)
        case .shrink:
            let minimum = min(span.length, screen.length * options.minimumSizeFraction)
            length = max(span.length - options.resizeStep, minimum)
            guard length < span.length else { return span }
        }

        let start: CGFloat
        switch (span.touchesLeadingEdge(of: screen), span.touchesTrailingEdge(of: screen)) {
        case (true, false):
            start = span.start
        case (false, true):
            start = span.end - length
        case (true, true), (false, false):
            start = span.start - (length - span.length) / 2
        }
        return clamped(Span(start: start, length: length), within: screen)
    }
}
