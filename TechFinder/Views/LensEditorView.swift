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
    @State private var circleRows: [CircleRow]
    @FocusState private var focusedField: Field?
    @State private var confirmsDelete = false

    /// One image circle figure being edited.
    private struct CircleRow: Identifiable {
        let id = UUID()
        var diameterText: String
        var fNumber: Double
    }

    /// Apertures manufacturers quote image circles at: the standard whole stops.
    private static let quotedApertures: [Double] = [2.8, 4, 5.6, 8, 11, 16, 22, 32, 45, 64]

    private enum Field { case focalLength, name }

    init(item: LensEditorItem, isRoot: Bool = false) {
        self.item = item
        self.isRoot = isRoot
        _name = State(initialValue: item.lens.name)
        _focalLengthText = State(initialValue: item.isNew ? "" : item.lens.focalLengthLabel)
        _circleRows = State(initialValue: item.lens.imageCircle.map {
            CircleRow(diameterText: Millimetres.label($0.diameter), fNumber: $0.fNumber)
        })
    }

    /// A sensible aperture for a new row: f/11 first, then the widest quoted aperture not yet used.
    private var nextAperture: Double {
        let used = Set(circleRows.map(\.fNumber))
        if !used.contains(11) { return 11 }
        return Self.quotedApertures.first { !used.contains($0) } ?? 22
    }

    /// The valid image circle figures entered so far.
    private var imageCircle: [ImageCirclePoint] {
        circleRows.compactMap { row in
            Double.parseMillimetres(row.diameterText).map { ImageCirclePoint(diameter: $0, fNumber: row.fNumber) }
        }
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

            imageCircleSection(format: format)

            if !item.isNew {
                Section {
                    Button("Delete Lens", role: .destructive) { confirmsDelete = true }
                        .confirmationDialog("Delete \(item.lens.displayName)?", isPresented: $confirmsDelete,
                                            titleVisibility: .visible) {
                            Button("Delete Lens", role: .destructive) {
                                library.deleteLens(id: item.lens.id)
                                finish()
                            }
                        } message: {
                            Text("Its image circle figures are deleted too.")
                        }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
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
        lens.imageCircle = imageCircle
        library.save(lens)
        if item.isNew {
            library.selectedLensID = lens.id
        }
        finish()
    }

    @ViewBuilder
    private func imageCircleSection(format: CaptureFormat) -> some View {
        Section {
            ForEach($circleRows) { $row in
                HStack {
                    TextField("90", text: $row.diameterText)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 64)
                    Text("mm at")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Aperture", selection: $row.fNumber) {
                        // A figure saved at another aperture keeps its place in the list.
                        ForEach(Self.quotedApertures.contains(row.fNumber) ? Self.quotedApertures
                                    : (Self.quotedApertures + [row.fNumber]).sorted(), id: \.self) { stop in
                            Text("f/\(Millimetres.label(stop))").tag(stop)
                        }
                    }
                    .labelsHidden()
                }
            }
            .onDelete { circleRows.remove(atOffsets: $0) }

            Button(circleRows.isEmpty ? "Add Image Circle" : "Add Another Aperture") {
                circleRows.append(CircleRow(diameterText: "", fNumber: nextAperture))
            }

            if let largest = imageCircle.max(by: { $0.fNumber < $1.fNumber }) {
                let geometry = MovementGeometry(format: format, riseAlongLongSide: true)
                let rise = geometry.maximum(.rise, other: 0, imageCircle: largest.diameter, limits: .unlimited)
                let shift = geometry.maximum(.shift, other: 0, imageCircle: largest.diameter, limits: .unlimited)
                LabeledContent("Rise or Fall", value: "±\(Millimetres.label(rise)) mm")
                LabeledContent("Shift", value: "±\(Millimetres.label(shift)) mm")
            }
        } header: {
            Text("Image Circle")
        } footer: {
            Text("From the lens data sheet: Rodenstock quotes f/11, Schneider and most large-format lenses f/22. Add figures at more apertures, such as wide open, to follow how coverage changes; apertures in between are interpolated in stops. Movements shown are for \(format.name) held upright, at the smallest quoted aperture.")
        }
        .monospacedDigit()
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
