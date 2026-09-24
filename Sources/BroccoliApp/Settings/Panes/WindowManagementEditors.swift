import BroccoliCore
import SwiftUI

/// Edits one saved custom layout. Nothing is saved until the user chooses Save.
struct CustomWindowLayoutEditor: View {
    let isNew: Bool
    let onSave: (CustomWindowLayout) -> Void
    let onCancel: () -> Void

    @State private var layout: CustomWindowLayout

    init(
        layout: CustomWindowLayout,
        isNew: Bool,
        onSave: @escaping (CustomWindowLayout) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _layout = State(initialValue: layout)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $layout.name)
                WindowDimensionField(title: "Width", dimension: $layout.width)
                WindowDimensionField(title: "Height", dimension: $layout.height)
                Picker("Position", selection: $layout.anchor) {
                    ForEach(WindowAnchor.allCases, id: \.self) { anchor in
                        Text(anchor.title).tag(anchor)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Layout" : "Save") {
                    var saved = layout
                    saved.sanitize()
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
    }
}

/// A number with a Points or Percent unit.
private struct WindowDimensionField: View {
    let title: String
    @Binding var dimension: WindowDimension

    private enum Unit: String, CaseIterable {
        case points = "pt"
        case percent = "%"
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, value: valueBinding, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Picker(title, selection: unitBinding) {
                    ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 90)
            }
        }
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: {
                switch dimension {
                case .points(let value), .percent(let value): value
                }
            },
            set: { newValue in
                switch dimension {
                case .points: dimension = .points(newValue)
                case .percent: dimension = .percent(newValue)
                }
            }
        )
    }

    private var unitBinding: Binding<Unit> {
        Binding(
            get: {
                if case .points = dimension { return .points }
                return .percent
            },
            set: { unit in
                switch (unit, dimension) {
                case (.points, .percent): dimension = .points(800)
                case (.percent, .points): dimension = .percent(50)
                default: break
                }
            }
        )
    }
}

/// Names a workspace, then records the windows currently on screen.
struct WindowWorkspaceSaveSheet: View {
    let onSave: (String) async -> String?
    let onDone: () -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $name)
                Text("Broccoli records which apps have windows open on each display and where those windows are. Window titles and contents are not saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            HStack {
                if isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Save Workspace") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
    }

    private func save() async {
        isSaving = true
        errorMessage = await onSave(name)
        isSaving = false
        if errorMessage == nil { onDone() }
    }
}
