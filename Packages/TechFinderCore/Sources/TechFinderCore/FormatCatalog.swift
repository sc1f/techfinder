import Foundation

/// Built-in formats. Film sizes are typical image areas; they vary a little between cameras and holders,
/// so photographers who need exact numbers can add a custom format.
public enum FormatCatalog {
    public static let presets: [CaptureFormat] = [
        // Digital backs, grouped by sensor size
        CaptureFormat(id: "digital-53.4x40", name: "53.4 × 40", width: 53.4, height: 40.0, category: .digitalBack,
                      models: ["Phase One IQ4 150MP", "IQ4 150MP Achromatic"]),
        CaptureFormat(id: "digital-53.7x40.4", name: "53.7 × 40.4", width: 53.7, height: 40.4, category: .digitalBack,
                      models: ["Phase One IQ3 100MP", "IQ 80MP", "IQ 60MP (53.9 × 40.4)", "Leaf Credo 80"]),
        CaptureFormat(id: "digital-44x33", name: "44 × 33", width: 43.8, height: 32.9, category: .digitalBack,
                      models: ["Hasselblad CFV 100C", "CFV II 50C", "Fujifilm GFX", "Phase One IQ 50MP"]),
        CaptureFormat(id: "digital-45x30", name: "45 × 30", width: 45.0, height: 30.0, category: .digitalBack,
                      models: ["Leica S"]),

        // Medium format film
        CaptureFormat(id: "film-645", name: "6×4.5", width: 56.0, height: 41.5, category: .mediumFormatFilm),
        CaptureFormat(id: "film-66", name: "6×6", width: 56.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-67", name: "6×7", width: 69.5, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-68", name: "6×8", width: 76.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-69", name: "6×9", width: 84.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-612", name: "6×12", width: 112.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-617", name: "6×17", width: 168.0, height: 56.0, category: .mediumFormatFilm),

        // Large format film
        CaptureFormat(id: "film-4x5", name: "4×5", width: 120.0, height: 96.0, category: .largeFormatFilm),
        CaptureFormat(id: "film-5x7", name: "5×7", width: 170.0, height: 120.0, category: .largeFormatFilm),
        CaptureFormat(id: "film-8x10", name: "8×10", width: 245.0, height: 194.0, category: .largeFormatFilm),

        // Small format
        CaptureFormat(id: "36x24", name: "36 × 24", width: 36.0, height: 24.0, category: .smallFormat,
                      models: ["Full-frame digital", "35mm film"]),
    ]

    public static let defaultFormatID = "digital-53.4x40"

    public static var defaultFormat: CaptureFormat {
        presets.first { $0.id == defaultFormatID }!
    }

    /// Preset ids from before digital backs were grouped by sensor size, mapped to their group.
    public static let legacyFormatIDs: [String: String] = [
        "phaseone-iq4-150": "digital-53.4x40",
        "phaseone-iq3-100": "digital-53.7x40.4",
        "phaseone-iq-80": "digital-53.7x40.4",
        "phaseone-iq-60": "digital-53.7x40.4",
        "phaseone-iq-50": "digital-44x33",
        "hasselblad-cfv-100c": "digital-44x33",
        "hasselblad-cfv-50c": "digital-44x33",
        "fujifilm-gfx": "digital-44x33",
        "leica-s": "digital-45x30",
        "full-frame": "36x24",
        "film-135": "36x24",
    ]

    /// A starting kit for first launch, typical of a digital technical camera.
    public static let starterLenses: [Lens] = [
        Lens(name: "HR Digaron-W 23", focalLength: 23),
        Lens(name: "HR Digaron-S 32", focalLength: 32),
        Lens(name: "HR Digaron-S 50", focalLength: 50),
        Lens(name: "HR Digaron-S 70", focalLength: 70),
    ]
}
