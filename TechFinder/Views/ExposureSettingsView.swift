import SwiftUI
import TechFinderCore

/// The equipment limits the light meter warns about: ISO, aperture and shutter ranges.
struct ExposureSettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePanel) private var closePanel

    var body: some View {
        NavigationStack {
            Form {
                limitSection(.iso, title: "ISO", lower: "Lowest", upper: "Highest",
                             footer: "The ISO range of your back or film.")
                limitSection(.aperture, title: "Aperture", lower: "Widest", upper: "Smallest",
                             footer: "The apertures your lenses offer.")
                limitSection(.shutter, title: "Shutter", lower: "Fastest", upper: "Slowest",
                             footer: "Leaf shutters usually top out at 1/500 s.")

                Section {
                    Button("Reset to Defaults") {
                        library.exposureLimits = .default
                    }
                    .disabled(library.exposureLimits == .default)
                } footer: {
                    Text("Meter values outside these limits turn orange.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
    }

    private func close() {
        if let closePanel { closePanel() } else { dismiss() }
    }

    private func limitSection(_ axis: ExposureAxis, title: String, lower: String, upper: String,
                              footer: String) -> some View {
        let range = library.exposureLimits.range(axis)
        let all = ExposureScale.range(axis)

        return Section {
            Picker(lower, selection: bound(axis, lower: true)) {
                ForEach(all.lowerBound...range.upperBound, id: \.self) { index in
                    Text(ExposureScale.label(axis, index)).tag(index)
                }
            }
            Picker(upper, selection: bound(axis, lower: false)) {
                ForEach(range.lowerBound...all.upperBound, id: \.self) { index in
                    Text(ExposureScale.label(axis, index)).tag(index)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
        .pickerStyle(.menu)
        .monospacedDigit()
    }

    private func bound(_ axis: ExposureAxis, lower: Bool) -> Binding<Int> {
        Binding {
            let range = library.exposureLimits.range(axis)
            return lower ? range.lowerBound : range.upperBound
        } set: { index in
            let range = library.exposureLimits.range(axis)
            library.exposureLimits.setRange(axis, lower ? index...max(index, range.upperBound)
                                                         : min(index, range.lowerBound)...index)
        }
    }
}
