@preconcurrency import AppKit
import SwiftUI

enum LauncherDesignChooserLayout {
    static let designs: [LauncherDesign] = [.liquidGlass, .minimal]
    static let accessibilityLabel = "Launcher Design"
    static let thumbnailWidth: CGFloat = 128
    static let thumbnailPadding: CGFloat = 6
    static let thumbnailSpacing: CGFloat = 8
    static let wellCornerRadius: CGFloat = 7
    static let selectedLineWidth: CGFloat = 2
    static let unselectedLineWidth: CGFloat = 1

    static var pickerWidth: CGFloat {
        let count = CGFloat(designs.count)
        return count * thumbnailWidth + max(0, count - 1) * thumbnailSpacing
    }

    /// Shared well height, fitted to the production Liquid Glass screenshot aspect.
    /// Minimal uses the same well so the two cards stay aligned.
    static var thumbnailHeight: CGFloat {
        let productionWidth = LauncherLiquidGlassMetrics.width
        let resultCount = CGFloat(LauncherPreviewFixture.standard.results.count)
        let productionHeight = LauncherLiquidGlassMetrics.searchHeight
            + LauncherLiquidGlassMetrics.resultTopInset
            + resultCount * LauncherLiquidGlassMetrics.searchHeight
            + LauncherLiquidGlassMetrics.resultBottomInset
        return fittedImageSize(
            for: CGSize(width: productionWidth, height: productionHeight)
        ).height + thumbnailPadding * 2
    }

    static func fittedImageSize(for productionSize: CGSize) -> CGSize {
        guard productionSize.width > 0, productionSize.height > 0 else { return .zero }
        let availableWidth = max(1, thumbnailWidth - thumbnailPadding * 2)
        let scale = availableWidth / productionSize.width
        return CGSize(
            width: productionSize.width * scale,
            height: productionSize.height * scale
        )
    }

    static func neighbor(of design: LauncherDesign, offset: Int) -> LauncherDesign? {
        guard let index = designs.firstIndex(of: design) else { return nil }
        let next = index + offset
        guard designs.indices.contains(next) else { return nil }
        return designs[next]
    }
}

struct LauncherDesignChooser: View {
    @Binding var selection: LauncherDesign
    let appearance: LauncherAppearancePreferences
    @ObservedObject var renderer: LauncherPreviewRenderer

    var body: some View {
        HStack(spacing: LauncherDesignChooserLayout.thumbnailSpacing) {
            ForEach(LauncherDesignChooserLayout.designs) { design in
                designCard(design)
            }
        }
        .frame(width: LauncherDesignChooserLayout.pickerWidth, alignment: .trailing)
        .focusable()
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
            VStack(spacing: 6) {
                LauncherDesignPreviewThumbnail(
                    design: design,
                    appearance: appearance,
                    renderer: renderer
                )
                .frame(
                    width: LauncherDesignChooserLayout.thumbnailWidth,
                    height: LauncherDesignChooserLayout.thumbnailHeight
                )
                .background {
                    RoundedRectangle(
                        cornerRadius: LauncherDesignChooserLayout.wellCornerRadius,
                        style: .continuous
                    )
                    .fill(.quaternary.opacity(0.4))
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: LauncherDesignChooserLayout.wellCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: LauncherDesignChooserLayout.wellCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.16),
                        lineWidth: isSelected
                            ? LauncherDesignChooserLayout.selectedLineWidth
                            : LauncherDesignChooserLayout.unselectedLineWidth
                    )
                }

                Text(design.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: LauncherDesignChooserLayout.thumbnailWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityHidden(true)
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

private struct LauncherDesignPreviewThumbnail: View {
    let design: LauncherDesign
    let appearance: LauncherAppearancePreferences
    @ObservedObject var renderer: LauncherPreviewRenderer
    @State private var renderedImage: NSImage?

    private var previewPreferences: LauncherAppearancePreferences {
        var preferences = appearance
        preferences.design = design
        return preferences
    }

    var body: some View {
        let displayed = renderedImage ?? renderer.cachedImage(for: previewPreferences)
        ZStack {
            if let displayed {
                Image(nsImage: displayed)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .padding(LauncherDesignChooserLayout.thumbnailPadding)
        .task(id: renderer.renderIdentity(for: previewPreferences)) {
            renderedImage = renderer.cachedImage(for: previewPreferences)
            renderedImage = await renderer.image(for: previewPreferences)
        }
    }
}
