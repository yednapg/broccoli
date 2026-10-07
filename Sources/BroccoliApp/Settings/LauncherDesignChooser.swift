@preconcurrency import AppKit
import SwiftUI

enum LauncherDesignChooserLayout {
    static let designs: [LauncherDesign] = [.liquidGlass, .minimal]
    static let accessibilityLabel = "Launcher Design"
    static let thumbnailWidth: CGFloat = 120
    /// Shared well for the closer launcher frames. The taller shot sets the
    /// height so neither background is clipped.
    static let artworkPixelSize = CGSize(width: 1024, height: 718)
    static let thumbnailSpacing: CGFloat = 8
    static let titleSpacing: CGFloat = 6
    static let wellCornerRadius: CGFloat = 10
    static let selectedLineWidth: CGFloat = 2
    static let unselectedLineWidth: CGFloat = 1
    static let unselectedStrokeNSColor: NSColor = .separatorColor
    /// Hide the group focus ring so keyboard focus cannot paint both thumbnails at once.
    static let disablesGroupFocusEffect = true

    static var unselectedStroke: Color { Color(nsColor: unselectedStrokeNSColor) }
    static var selectedStroke: Color { Color.accentColor }

    static var pickerWidth: CGFloat {
        let count = CGFloat(designs.count)
        return count * thumbnailWidth + max(0, count - 1) * thumbnailSpacing
    }

    static var selectionWellSize: CGSize {
        CGSize(width: thumbnailWidth, height: thumbnailHeight)
    }

    static var thumbnailHeight: CGFloat {
        thumbnailWidth * artworkPixelSize.height / artworkPixelSize.width
    }

    static func neighbor(of design: LauncherDesign, offset: Int) -> LauncherDesign? {
        guard let index = designs.firstIndex(of: design) else { return nil }
        let next = index + offset
        guard designs.indices.contains(next) else { return nil }
        return designs[next]
    }

    /// Local well for a design, in chooser coordinates with origin at the top-leading card.
    static func selectionWellFrame(for design: LauncherDesign) -> CGRect {
        guard let index = designs.firstIndex(of: design) else { return .zero }
        let x = CGFloat(index) * (thumbnailWidth + thumbnailSpacing)
        return CGRect(origin: CGPoint(x: x, y: 0), size: selectionWellSize)
    }

    /// Clickable card, including the caption under the well. Wells stay exclusive.
    static func cardFrame(for design: LauncherDesign) -> CGRect {
        let well = selectionWellFrame(for: design)
        return CGRect(
            x: well.minX,
            y: well.minY,
            width: well.width,
            height: well.height + titleSpacing + 16
        )
    }

    static func design(at point: CGPoint) -> LauncherDesign? {
        designs.first { cardFrame(for: $0).contains(point) }
    }
}

/// Title plus independent design cards. Kept out of `SpotlightSettingsRow` so the row
/// HStack cannot share focus or selection chrome with the thumbnails.
struct LauncherDesignChooserRow: View {
    @Binding var selection: LauncherDesign

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(LauncherDesignChooserLayout.accessibilityLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            LauncherDesignChooser(selection: $selection)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct LauncherDesignChooser: View {
    @Binding var selection: LauncherDesign

    var body: some View {
        HStack(spacing: LauncherDesignChooserLayout.thumbnailSpacing) {
            ForEach(LauncherDesignChooserLayout.designs) { design in
                designCard(design)
            }
        }
        .frame(width: LauncherDesignChooserLayout.pickerWidth, alignment: .trailing)
        .focusable()
        .focusEffectDisabled(LauncherDesignChooserLayout.disablesGroupFocusEffect)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LauncherDesignChooserLayout.accessibilityLabel)
        .accessibilityValue(selection.title)
        .accessibilityAdjustableAction(adjustSelection)
        .accessibilityRepresentation {
            Picker(LauncherDesignChooserLayout.accessibilityLabel, selection: $selection) {
                ForEach(LauncherDesignChooserLayout.designs) { design in
                    Text(design.title).tag(design)
                }
            }
        }
    }

    private func designCard(_ design: LauncherDesign) -> some View {
        let isSelected = selection == design
        return Button {
            selection = design
        } label: {
            VStack(spacing: LauncherDesignChooserLayout.titleSpacing) {
                thumbnailWell(for: design, isSelected: isSelected)

                Text(design.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: LauncherDesignChooserLayout.thumbnailWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(LauncherDesignCardButtonStyle())
        .focusable(false)
        .accessibilityHidden(true)
    }

    private func thumbnailWell(for design: LauncherDesign, isSelected: Bool) -> some View {
        let well = RoundedRectangle(
            cornerRadius: LauncherDesignChooserLayout.wellCornerRadius,
            style: .continuous
        )
        return LauncherDesignPreviewThumbnail(design: design)
        .frame(
            width: LauncherDesignChooserLayout.thumbnailWidth,
            height: LauncherDesignChooserLayout.thumbnailHeight
        )
        .background {
            well.fill(.quaternary.opacity(0.4))
        }
        .clipShape(well)
        .overlay {
            well.strokeBorder(
                isSelected
                    ? LauncherDesignChooserLayout.selectedStroke
                    : LauncherDesignChooserLayout.unselectedStroke,
                lineWidth: isSelected
                    ? LauncherDesignChooserLayout.selectedLineWidth
                    : LauncherDesignChooserLayout.unselectedLineWidth
            )
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let offset: Int = switch direction {
        case .left, .up: -1
        case .right, .down: 1
        default: 0
        }
        guard offset != 0,
              let next = LauncherDesignChooserLayout.neighbor(of: selection, offset: offset)
        else { return }
        selection = next
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let offset = direction == .increment ? 1 : -1
        if let next = LauncherDesignChooserLayout.neighbor(of: selection, offset: offset) {
            selection = next
        }
    }
}

/// Avoids the default macOS button fill, which can paint the whole settings row.
private struct LauncherDesignCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

enum LauncherDesignArtwork {
    static func image(for design: LauncherDesign) -> NSImage? {
        let name = switch design {
        case .liquidGlass: "LauncherDesignLiquidGlass"
        case .minimal: "LauncherDesignMinimal"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct LauncherDesignPreviewThumbnail: View {
    let design: LauncherDesign

    var body: some View {
        if let image = LauncherDesignArtwork.image(for: design) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}
