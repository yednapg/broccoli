import ApplicationServices
import CoreGraphics
@testable import BroccoliApp

/// A window that answers Accessibility the way an AppKit window does on a real display: a size
/// is cut short where the window would run off the screen from its current position, sizes
/// stay within the window's minimum and maximum, a grid-snapping window rounds to its cell, and
/// the top edge stays below the menu bar.
final class SimulatedWindow {
    let processIdentifier: pid_t
    let element: AXUIElement
    let screen: CGRect
    var frame: CGRect
    var minimumSize: CGSize
    var maximumSize: CGSize
    var resizeIncrement: CGSize?
    private(set) var writes: [String] = []
    /// Deliberate waits and error retries. A working window needs neither.
    private(set) var waits = 0

    init(
        frame: CGRect,
        screen: CGRect,
        minimumSize: CGSize = CGSize(width: 200, height: 150),
        maximumSize: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
        resizeIncrement: CGSize? = nil,
        processIdentifier: pid_t = 4_242
    ) {
        self.frame = frame
        self.screen = screen
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.resizeIncrement = resizeIncrement
        self.processIdentifier = processIdentifier
        element = AXUIElementCreateApplication(processIdentifier)
    }

    func makeOperation() -> WindowAccessibilityOperation {
        WindowAccessibilityOperation(
            attributeReader: { [self] _, attribute in read(attribute) },
            attributeWriter: { [self] _, attribute, value in write(attribute, value) },
            messagingTimeoutSetter: { _, _ in .success },
            retryWaiter: { [self] _ in waits += 1 },
            frameSettlementWaiter: { [self] _ in waits += 1 }
        )
    }

    private func read(_ attribute: CFString) -> AccessibilityAttributeRead {
        switch attribute as String {
        case kAXFocusedWindowAttribute, kAXMainWindowAttribute:
            return AccessibilityAttributeRead(error: .success, value: element)
        case kAXRoleAttribute:
            return AccessibilityAttributeRead(error: .success, value: kAXWindowRole as CFString)
        case kAXSubroleAttribute:
            return AccessibilityAttributeRead(error: .success, value: kAXStandardWindowSubrole as CFString)
        case kAXPositionAttribute:
            var origin = frame.origin
            return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgPoint, &origin))
        case kAXSizeAttribute:
            var size = frame.size
            return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgSize, &size))
        default:
            return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
        }
    }

    private func write(_ attribute: CFString, _ value: CFTypeRef) -> AXError {
        let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
        switch attribute as String {
        case kAXSizeAttribute:
            writes.append("size")
            var requested = CGSize.zero
            AXValueGetValue(accessibilityValue, .cgSize, &requested)
            frame.size = CGSize(
                width: length(requested.width, axis: \.width, room: screen.maxX - frame.minX),
                height: length(requested.height, axis: \.height, room: screen.maxY - frame.minY)
            )
            return .success
        case kAXPositionAttribute:
            writes.append("position")
            var requested = CGPoint.zero
            AXValueGetValue(accessibilityValue, .cgPoint, &requested)
            frame.origin = CGPoint(x: requested.x, y: max(requested.y, screen.minY))
            return .success
        default:
            return .attributeUnsupported
        }
    }

    private func length(_ requested: CGFloat, axis: KeyPath<CGSize, CGFloat>, room: CGFloat) -> CGFloat {
        let minimum = minimumSize[keyPath: axis]
        var length = min(max(requested, minimum), maximumSize[keyPath: axis])
        length = max(minimum, min(length, room))
        if let increment = resizeIncrement?[keyPath: axis], increment > 0 {
            length = minimum + ((length - minimum) / increment).rounded(.down) * increment
        }
        return length
    }
}
