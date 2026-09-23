import Foundation

/// Built-in formats. Film sizes are typical image areas; they vary a little between cameras and holders,
/// so photographers who need exact numbers can add a custom format.
public enum FormatCatalog {
    public static let presets: [CaptureFormat] = [
        // Digital backs
        CaptureFormat(id: "phaseone-iq4-150", name: "Phase One IQ4 150MP", width: 53.4, height: 40.0, category: .digitalBack),
        CaptureFormat(id: "phaseone-iq3-100", name: "Phase One IQ3 100MP", width: 53.7, height: 40.4, category: .digitalBack),
        CaptureFormat(id: "phaseone-iq-80", name: "Phase One IQ 80MP", width: 53.7, height: 40.4, category: .digitalBack),
        CaptureFormat(id: "phaseone-iq-60", name: "Phase One IQ 60MP", width: 53.9, height: 40.4, category: .digitalBack),
        CaptureFormat(id: "phaseone-iq-50", name: "Phase One IQ 50MP", width: 43.9, height: 32.9, category: .digitalBack),
        CaptureFormat(id: "hasselblad-cfv-100c", name: "Hasselblad CFV 100C", width: 43.8, height: 32.9, category: .digitalBack),
        CaptureFormat(id: "hasselblad-cfv-50c", name: "Hasselblad CFV II 50C", width: 43.8, height: 32.9, category: .digitalBack),
        CaptureFormat(id: "fujifilm-gfx", name: "Fujifilm GFX", width: 43.8, height: 32.9, category: .digitalBack),
        CaptureFormat(id: "leica-s", name: "Leica S", width: 45.0, height: 30.0, category: .digitalBack),
        CaptureFormat(id: "full-frame", name: "Full Frame (35mm digital)", width: 36.0, height: 24.0, category: .digitalBack),

        // Medium format film
        CaptureFormat(id: "film-645", name: "6×4.5", width: 56.0, height: 41.5, category: .mediumFormatFilm),
        CaptureFormat(id: "film-66", name: "6×6", width: 56.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-67", name: "6×7", width: 69.5, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-68", name: "6×8", width: 76.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-69", name: "6×9", width: 84.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-612", name: "6×12", width: 112.0, height: 56.0, category: .mediumFormatFilm),
        CaptureFormat(id: "film-617", name: "6×17", width: 168.0, height: 56.0, category: .mediumFormatFilm),

        // Large format film
        CaptureFormat(id: "film-4x5", name: "4×5 in", width: 120.0, height: 96.0, category: .largeFormatFilm),
        CaptureFormat(id: "film-5x7", name: "5×7 in", width: 170.0, height: 120.0, category: .largeFormatFilm),
        CaptureFormat(id: "film-8x10", name: "8×10 in", width: 245.0, height: 194.0, category: .largeFormatFilm),

        // Small format
        CaptureFormat(id: "film-135", name: "35mm Film", width: 36.0, height: 24.0, category: .smallFormat),
    ]

    public static let defaultFormatID = "phaseone-iq4-150"

    public static var defaultFormat: CaptureFormat {
        presets.first { $0.id == defaultFormatID }!
    }

    /// A starting kit for first launch, typical of a digital technical camera.
    public static let starterLenses: [Lens] = [
        Lens(name: "HR Digaron-W 23", focalLength: 23),
        Lens(name: "HR Digaron-S 32", focalLength: 32),
        Lens(name: "HR Digaron-S 50", focalLength: 50),
        Lens(name: "HR Digaron-S 70", focalLength: 70),
    ]
}
