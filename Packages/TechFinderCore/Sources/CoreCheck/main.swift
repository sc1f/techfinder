// Minimal assertions for environments without XCTest (Command Line Tools only).
// The full suite lives in Tests/TechFinderCoreTests and runs from Xcode.
import Foundation
import TechFinderCore

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

let fullFrame = CaptureFormat(id: "ff", name: "FF", width: 36, height: 24, category: .smallFormat)
let optics = CameraOptics(horizontalFieldOfView: 108.3, aspectRatio: 4.0 / 3.0, minZoom: 1, maxZoom: 15)

let fov = FieldOfView(focalLength: 50, format: fullFrame)
check(near(fov.long, 39.6, 0.05), "50mm FF long angle \(fov.long)")
check(near(fov.short, 27.0, 0.05), "50mm FF short angle \(fov.short)")
check(near(fov.diagonal, 46.8, 0.05), "50mm FF diagonal \(fov.diagonal)")
check(near(Framing.equivalentFocalLength(focalLength: 23, format: FormatCatalog.defaultFormat), 14.9, 0.05), "23mm on IQ4 equivalent")

let normal = Framing.solve(focalLength: 50, format: fullFrame, optics: optics, fill: 0.85)
check(near(normal.longFraction, 0.85, 1e-9), "fill long axis \(normal.longFraction)")
check(normal.shortFraction < 0.85 && !normal.isClipped, "short axis inside")

let iq4 = FormatCatalog.defaultFormat
let s32 = Framing.solve(focalLength: 32, format: iq4, optics: optics)
check(near(s32.longFraction * optics.tanHalfLong / s32.zoom, iq4.longSide / 64, 1e-9), "long tangent matches")
check(near(s32.shortFraction * optics.tanHalfShort / s32.zoom, iq4.shortSide / 64, 1e-9), "short tangent matches")

let square = Framing.solve(focalLength: 80, format: FormatCatalog.presets.first { $0.id == "film-66" }!, optics: optics, fill: 0.9)
check(near(square.shortFraction, 0.9, 1e-9) && near(square.longFraction, 0.675, 1e-9), "square limited by short axis")

let panoramic = Framing.solve(focalLength: 35, format: CaptureFormat(id: "617", name: "", width: 168, height: 56, category: .custom), optics: optics)
check(panoramic.zoom == 1 && panoramic.isClipped, "6x17 35mm clipped")
check(Framing.solve(focalLength: 1200, format: fullFrame, optics: optics).zoom == 15, "max zoom clamp")

// Store round trip
let url = FileManager.default.temporaryDirectory.appendingPathComponent("tf-check-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: url) }
let store = LibraryStore(fileURL: url)
check(store.selectedLens?.focalLength == 50, "starter selection")
let lens = Lens(name: "Apo-Sironar 40", focalLength: 40)
store.save(lens)
store.selectedLensID = lens.id
let custom = CaptureFormat.custom(name: "Cropped", width: 90, height: 115)
store.save(custom)
store.selectedFormatID = custom.id
let reloaded = LibraryStore(fileURL: url)
check(reloaded.lenses.map(\.focalLength) == [23, 32, 40, 50, 70], "sorted lenses \(reloaded.lenses.map(\.focalLength))")
check(reloaded.selectedLens == lens, "lens selection persisted")
check(reloaded.selectedFormat.longSide == 115 && reloaded.selectedFormat.shortSide == 90, "custom format persisted")
reloaded.deleteLens(id: lens.id)
check(reloaded.selectedLens?.focalLength == 50, "neighbour after delete")
reloaded.deleteFormat(id: custom.id)
check(reloaded.selectedFormat.id == FormatCatalog.defaultFormatID, "format fallback")
check(Lens(name: " ", focalLength: 23.5).displayName == "23.5 mm", "display name fallback")

print(String(format: "Sample: 32mm on IQ4 → zoom %.2fx, frame %.0f%% × %.0f%%, %@, %@",
             s32.zoom, s32.longFraction * 100, s32.shortFraction * 100,
             FieldOfView(focalLength: 32, format: iq4).anglesLabel, FieldOfView(focalLength: 32, format: iq4).equivalentLabel))
print(failures == 0 ? "All core checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
