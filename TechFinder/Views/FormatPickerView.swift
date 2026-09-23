import SwiftUI
import TechFinderCore

/// Chooses the digital back or film format the frame is drawn for.
struct FormatPickerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var editor: FormatEditorItem?

    private let presetCategories = CaptureFormat.Category.allCases.filter { $0 != .custom }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(presetCategories, id: \.self) { category in
                        Section(category.title) {
                            ForEach(FormatCatalog.presets.filter { $0.category == category }) { format in
                                row(for: format)
                            }
                        }
                    }

                    Section {
                        ForEach(library.customFormats) { format in
                            row(for: format)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        library.deleteFormat(id: format.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        editor = .edit(format)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editor = .edit(format) }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        library.deleteFormat(id: format.id)
                                    }
                                }
                        }
                        Button {
                            editor = .new()
                        } label: {
                            Label("Add Custom Format", systemImage: "plus")
                        }
                    } header: {
                        Text(CaptureFormat.Category.custom.title)
                    } footer: {
                        Text("Film sizes are typical image areas. Add a custom format for a specific back, holder or crop.")
                    }
                }
                .onAppear {
                    proxy.scrollTo(library.selectedFormatID, anchor: .center)
                }
            }
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editor) { item in
                FormatEditorView(item: item)
            }
        }
    }

    private func row(for format: CaptureFormat) -> some View {
        Button {
            library.selectedFormatID = format.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.name)
                    Text(format.dimensionsLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if format.id == library.selectedFormatID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(format.id)
    }
}

struct FormatEditorItem: Identifiable {
    let format: CaptureFormat
    let isNew: Bool
    var id: String { format.id }

    static func new() -> FormatEditorItem {
        FormatEditorItem(format: .custom(name: "", width: 0, height: 0), isNew: true)
    }

    static func edit(_ format: CaptureFormat) -> FormatEditorItem {
        FormatEditorItem(format: format, isNew: false)
    }
}

/// Creates or edits a custom format from its image-area dimensions.
struct FormatEditorView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    let item: FormatEditorItem
    @State private var name: String
    @State private var widthText: String
    @State private var heightText: String

    init(item: FormatEditorItem) {
        self.item = item
        _name = State(initialValue: item.format.name)
        _widthText = State(initialValue: item.isNew ? "" : Millimetres.label(item.format.longSide))
        _heightText = State(initialValue: item.isNew ? "" : Millimetres.label(item.format.shortSide))
    }

    private var dimensions: (width: Double, height: Double)? {
        guard let width = Double.parseMillimetres(widthText), let height = Double.parseMillimetres(heightText),
              CaptureFormat.sideRange.contains(width), CaptureFormat.sideRange.contains(height) else { return nil }
        return (width, height)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    dimensionField("Width", text: $widthText)
                    dimensionField("Height", text: $heightText)
                } footer: {
                    Text("The exposed image area in millimetres. Hold the phone the way the back is mounted; the frame follows.")
                }

                if let dimensions {
                    Section {
                        HStack {
                            Spacer()
                            AspectPreview(width: dimensions.width, height: dimensions.height)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(item.isNew ? "New Format" : "Edit Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(dimensions == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func dimensionField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("mm")
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let dimensions else { return }
        var format = item.format
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        format.setDimensions(width: dimensions.width, height: dimensions.height)
        format.name = trimmed.isEmpty ? format.dimensionsLabel : trimmed
        library.save(format)
        library.selectedFormatID = format.id
        dismiss()
    }
}

private struct AspectPreview: View {
    let width: Double
    let height: Double

    var body: some View {
        let scale = 110 / max(width, height)
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(.tint, lineWidth: 1.5)
            .frame(width: width * scale, height: height * scale)
            .frame(height: 120)
            .animation(.smooth, value: width / height)
    }
}
