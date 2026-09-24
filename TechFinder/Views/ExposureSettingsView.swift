import SwiftUI
import TechFinderCore

/// Equipment limits: the ISO, aperture and shutter ranges the light meter warns about, and how far the
/// camera's movements go.
struct ExposureSettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePanel) private var closePanel
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Steps", selection: Binding(get: { library.meterStep }, set: { library.meterStep = $0 })) {
                        Text("Full Stop").tag(3)
                        Text("⅓ Stop").tag(1)
                    }
                    Stepper(value: Binding(get: { library.meterCalibration },
                                           set: { library.meterCalibration = ($0 * 10).rounded() / 10 }),
                            in: -3...3, step: 0.1) {
                        LabeledContent("Calibration", value: String(format: "%+.1f EV", library.meterCalibration))
                    }
                    .monospacedDigit()
                } header: {
                    Text("Light Meter")
                } footer: {
                    Text("Steps: how far each arrow tap or swipe moves ISO, aperture and shutter. Calibration: compare the EV shown by ISO with a handheld spot meter on a grey card; if the app reads consistently high or low, offset it here.")
                }

                limitSection(.iso, title: "ISO", lower: "Lowest", upper: "Highest",
                             footer: "The ISO range of your back or film.")
                limitSection(.aperture, title: "Aperture", lower: "Widest", upper: "Smallest",
                             footer: "The apertures your lenses offer.")
                limitSection(.shutter, title: "Shutter", lower: "Fastest", upper: "Slowest",
                             footer: "The shutter speeds your camera and lenses offer.")

                Section {
                    movementStepper(.rise, title: "Rise/Fall")
                    movementStepper(.shift, title: "Shift")
                } header: {
                    Text("Camera Movements")
                } footer: {
                    Text("How far your camera moves either side of centre. Movements also stop at the lens's image circle.")
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) { confirmsReset = true }
                    .confirmationDialog("Reset the limits, movements and calibration?", isPresented: $confirmsReset,
                                        titleVisibility: .visible) {
                        Button("Reset to Defaults", role: .destructive) {
                            library.exposureLimits = .default
                            library.movementLimits = .default
                            library.meterCalibration = 0
                        }
                    }
                    .disabled(library.exposureLimits == .default && library.movementLimits == .default
                              && library.meterCalibration == 0)
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

    /// Lowest and highest limits for one axis, listing whole stops or thirds to match the meter's steps.
    private func limitSection(_ axis: ExposureAxis, title: String, lower: String, upper: String,
                              footer: String) -> some View {
        let range = library.exposureLimits.range(axis)
        let all = ExposureScale.range(axis)

        return Section {
            Picker(lower, selection: bound(axis, lower: true)) {
                ForEach(choices(axis, all.lowerBound...range.upperBound, current: range.lowerBound), id: \.self) { index in
                    Text(ExposureScale.label(axis, index)).tag(index)
                }
            }
            Picker(upper, selection: bound(axis, lower: false)) {
                ForEach(choices(axis, range.lowerBound...all.upperBound, current: range.upperBound), id: \.self) { index in
                    Text(ExposureScale.label(axis, index)).tag(index)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("\(footer) Metered values outside these limits turn orange.")
        }
        .pickerStyle(.menu)
        .monospacedDigit()
    }

    /// The scale values in `range` a limit can take: whole stops with full-stop steps, else thirds.
    /// The current value is always included so the picker shows it.
    private func choices(_ axis: ExposureAxis, _ range: ClosedRange<Int>, current: Int) -> [Int] {
        range.filter { $0 == current || library.meterStep == 1 || ExposureScale.isFullStop($0, axis: axis) }
    }

    private func movementStepper(_ axis: MovementAxis, title: String) -> some View {
        let value = library.movementLimits[axis]
        return Stepper(value: Binding(get: { value }, set: { library.movementLimits[axis] = $0 }), in: 0...60, step: 1) {
            LabeledContent(title, value: "±\(Millimetres.label(value)) mm")
        }
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
