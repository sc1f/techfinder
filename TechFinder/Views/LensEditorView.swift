import SwiftUI
import TechFinderCore

/// Creates or edits a lens: a focal length and an optional name.
///
/// Usually pushed from the lens library. As the root of its own sheet or panel (`isRoot`), it adds a
/// Cancel button and closes the whole presentation when done.
struct LensEditorView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePanel) private var closePanel

    let item: LensEditorItem
    let isRoot: Bool
    @State private var name: String
    @State private var focalLengthText: String
    @FocusState private var focusedField: Field?

    private enum Field { case focalLength, name }

    init(item: LensEditorItem, isRoot: Bool = false) {
        self.item = item
        self.isRoot = isRoot
        _name = State(initialValue: item.lens.name)
        _focalLengthText = State(initialValue: item.isNew ? "" : item.lens.focalLengthLabel)
    }

    private var focalLength: Double? {
        let value = Double.parseMillimetres(focalLengthText)
        return value.flatMap { Lens.focalLengthRange.contains($0) ? $0 : nil }
    }

    var body: some View {
        let format = library.selectedFormat

        Form {
            Section {
                HStack {
                    Text("Focal Length")
                    TextField("50", text: $focalLengthText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .focalLength)
                    Text("mm")
                        .foregroundStyle(.secondary)
                }
                TextField("Name (optional)", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done)
                    .onSubmit(save)
            }

            if let focalLength {
                let fov = FieldOfView(focalLength: focalLength, format: format)
                Section {
                    LabeledContent("Angle of View", value: fov.anglesLabel)
                    LabeledContent("Diagonal", value: String(format: "%.1f°", fov.diagonal))
                    LabeledContent("35mm Equivalent", value: fov.equivalentLabel)
                } header: {
                    Text("On \(format.name)")
                }
                .monospacedDigit()
            }

            if !item.isNew {
                Section {
                    Button("Delete Lens", role: .destructive) {
                        library.deleteLens(id: item.lens.id)
                        finish()
                    }
                }
            }
        }
        .navigationTitle(item.isNew ? "New Lens" : "Edit Lens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: finish)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(focalLength == nil)
            }
        }
        .onAppear {
            if item.isNew { focusedField = .focalLength }
        }
    }

    private func save() {
        guard let focalLength else { return }
        var lens = item.lens
        lens.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        lens.focalLength = focalLength
        library.save(lens)
        if item.isNew {
            library.selectedLensID = lens.id
        }
        finish()
    }

    /// Goes back to the library, or closes the presentation when this editor is its root.
    private func finish() {
        if isRoot, let closePanel { closePanel() } else { dismiss() }
    }
}

extension Double {
    /// Parses a user-typed millimetre value, accepting either decimal separator.
    static func parseMillimetres(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}
