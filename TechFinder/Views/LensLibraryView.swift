import SwiftUI
import TechFinderCore

/// Lists saved lenses. Tapping a lens puts it on the camera; edit and delete via the row button or a swipe.
struct LensLibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var editor: LensEditorItem?

    var body: some View {
        let format = library.selectedFormat

        NavigationStack {
            List {
                Section {
                    ForEach(library.lenses) { lens in
                        row(for: lens, format: format)
                    }
                } footer: {
                    if !library.lenses.isEmpty {
                        Text("Angles of view on \(format.name), long × short side.")
                    }
                }
            }
            .overlay {
                if library.lenses.isEmpty {
                    ContentUnavailableView {
                        Label("No Lenses", systemImage: "camera.aperture")
                    } description: {
                        Text("Add the lenses you shoot with to frame through them.")
                    } actions: {
                        Button("Add Lens") { editor = .new() }
                    }
                }
            }
            .navigationTitle("Lenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new()
                    } label: {
                        Label("Add Lens", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { item in
                LensEditorView(item: item)
            }
        }
    }

    private func row(for lens: Lens, format: CaptureFormat) -> some View {
        let isSelected = lens.id == library.selectedLensID
        let fov = FieldOfView(focalLength: lens.focalLength, format: format)

        return HStack(spacing: 12) {
            Button {
                library.selectedLensID = lens.id
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(lens.focalLengthLabel)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 44, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lens.displayName)
                        Text("\(fov.anglesLabel) · \(fov.equivalentLabel)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Selected")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editor = .edit(lens)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(lens.displayName)")
        }
        .swipeActions {
            Button(role: .destructive) {
                library.deleteLens(id: lens.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editor = .edit(lens)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}

struct LensEditorItem: Identifiable {
    let lens: Lens
    let isNew: Bool
    var id: UUID { lens.id }

    static func new() -> LensEditorItem { LensEditorItem(lens: Lens(name: "", focalLength: 0), isNew: true) }
    static func edit(_ lens: Lens) -> LensEditorItem { LensEditorItem(lens: lens, isNew: false) }
}
