import Foundation
import Observation

/// The photographer's lenses, custom formats and current setup, saved as JSON on every change.
@Observable
public final class LibraryStore {
    /// Always sorted by focal length, so the lens bar reads wide to long.
    public private(set) var lenses: [Lens] = []
    public private(set) var customFormats: [CaptureFormat] = []
    public var selectedLensID: Lens.ID? { didSet { save() } }
    public var selectedFormatID: CaptureFormat.ID { didSet { save() } }
    /// ISO, aperture, shutter and which one follows the light meter.
    public var exposure: ExposureSettings = .default { didSet { save() } }
    /// The equipment's ISO, aperture and shutter limits, for warnings.
    public var exposureLimits: ExposureLimits = .default { didSet { save() } }
    /// The camera's mechanical rise/fall and shift range.
    public var movementLimits: MovementLimits = .default { didSet { save() } }
    /// How far the meter's arrows and swipes move, in thirds of a stop: 3 for full stops, 1 for thirds.
    public var meterStep: Int = 3 { didSet { save() } }

    @ObservationIgnored private let fileURL: URL?

    /// - Parameter fileURL: Where to persist the library; `nil` keeps it in memory only.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        self.selectedFormatID = FormatCatalog.defaultFormatID

        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            lenses = snapshot.lenses.sorted(by: Self.lensOrder)
            customFormats = snapshot.customFormats
            selectedLensID = snapshot.selectedLensID
            selectedFormatID = FormatCatalog.legacyFormatIDs[snapshot.selectedFormatID] ?? snapshot.selectedFormatID
            exposure = snapshot.exposure ?? .default
            exposureLimits = snapshot.exposureLimits ?? .default
            movementLimits = snapshot.movementLimits ?? .default
            meterStep = snapshot.meterStep ?? 3
        } else {
            lenses = FormatCatalog.starterLenses.sorted(by: Self.lensOrder)
            selectedLensID = lenses.first(where: { $0.focalLength == 50 })?.id ?? lenses.first?.id
        }
        repairSelection()
    }

    /// The store backing the app, in Application Support.
    public static func appDefault() -> LibraryStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TechFinder", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
    }

    // MARK: Selection

    public var selectedLens: Lens? {
        lenses.first { $0.id == selectedLensID }
    }

    public var allFormats: [CaptureFormat] {
        FormatCatalog.presets + customFormats
    }

    public var selectedFormat: CaptureFormat {
        allFormats.first { $0.id == selectedFormatID } ?? FormatCatalog.defaultFormat
    }

    // MARK: Lenses

    /// Adds the lens, or replaces the one with the same id.
    public func save(_ lens: Lens) {
        if let index = lenses.firstIndex(where: { $0.id == lens.id }) {
            lenses[index] = lens
        } else {
            lenses.append(lens)
        }
        lenses.sort(by: Self.lensOrder)
        if selectedLensID == nil {
            selectedLensID = lens.id
        }
        save()
    }

    public func deleteLens(id: Lens.ID) {
        guard let index = lenses.firstIndex(where: { $0.id == id }) else { return }
        lenses.remove(at: index)
        if selectedLensID == id {
            // Fall to the neighbouring lens so the viewfinder keeps a sensible frame.
            selectedLensID = lenses.isEmpty ? nil : lenses[min(index, lenses.count - 1)].id
        }
        save()
    }

    // MARK: Custom formats

    public func save(_ format: CaptureFormat) {
        precondition(format.isCustom, "Only custom formats can be edited")
        if let index = customFormats.firstIndex(where: { $0.id == format.id }) {
            customFormats[index] = format
        } else {
            customFormats.append(format)
        }
        save()
    }

    public func deleteFormat(id: CaptureFormat.ID) {
        customFormats.removeAll { $0.id == id }
        if selectedFormatID == id {
            selectedFormatID = FormatCatalog.defaultFormatID
        }
        save()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var version = 1
        var lenses: [Lens]
        var customFormats: [CaptureFormat]
        var selectedLensID: Lens.ID?
        var selectedFormatID: CaptureFormat.ID
        // Added later; missing in older files.
        var exposure: ExposureSettings?
        var exposureLimits: ExposureLimits?
        var movementLimits: MovementLimits?
        var meterStep: Int?
    }

    private static func lensOrder(_ a: Lens, _ b: Lens) -> Bool {
        if a.focalLength != b.focalLength { return a.focalLength < b.focalLength }
        return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
    }

    private func repairSelection() {
        if selectedLens == nil {
            selectedLensID = lenses.first?.id
        }
        if !allFormats.contains(where: { $0.id == selectedFormatID }) {
            selectedFormatID = FormatCatalog.defaultFormatID
        }
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(lenses: lenses, customFormats: customFormats,
                                selectedLensID: selectedLensID, selectedFormatID: selectedFormatID,
                                exposure: exposure, exposureLimits: exposureLimits,
                                movementLimits: movementLimits, meterStep: meterStep)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save library: \(error)")
        }
    }
}
