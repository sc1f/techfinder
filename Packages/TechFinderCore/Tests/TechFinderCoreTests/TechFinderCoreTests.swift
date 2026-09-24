import XCTest
@testable import TechFinderCore

final class FramingTests: XCTestCase {
    private let fullFrame = CaptureFormat(id: "ff", name: "FF", width: 36, height: 24, category: .smallFormat)
    private let optics = CameraOptics(horizontalFieldOfView: 108.3, aspectRatio: 4.0 / 3.0, minZoom: 1, maxZoom: 15)

    func testAngleOfViewOfNormalLens() {
        let fov = FieldOfView(focalLength: 50, format: fullFrame)
        XCTAssertEqual(fov.long, 39.6, accuracy: 0.05)
        XCTAssertEqual(fov.short, 27.0, accuracy: 0.05)
        XCTAssertEqual(fov.diagonal, 46.8, accuracy: 0.05)
        XCTAssertEqual(fov.equivalentFocalLength, 50, accuracy: 0.001)
    }

    func testEquivalentFocalLengthOnDigitalBack() {
        let equivalent = Framing.equivalentFocalLength(focalLength: 23, format: FormatCatalog.defaultFormat)
        XCTAssertEqual(equivalent, 14.9, accuracy: 0.05)
    }

    func testFrameFillsRequestedFractionOfTighterAxis() {
        let solution = Framing.solve(focalLength: 50, format: fullFrame, optics: optics, fill: 0.85)
        XCTAssertEqual(solution.longFraction, 0.85, accuracy: 1e-9)
        XCTAssertLessThan(solution.shortFraction, 0.85)
        XCTAssertFalse(solution.isClipped)
    }

    func testFrameMatchesTargetAngleOfView() {
        // The frame's share of the zoomed phone image must equal the ratio of the tangents.
        let format = FormatCatalog.defaultFormat
        let solution = Framing.solve(focalLength: 32, format: format, optics: optics)
        let phoneTanLong = optics.tanHalfLong / solution.zoom
        let phoneTanShort = optics.tanHalfShort / solution.zoom
        XCTAssertEqual(solution.longFraction * phoneTanLong, format.longSide / 64, accuracy: 1e-9)
        XCTAssertEqual(solution.shortFraction * phoneTanShort, format.shortSide / 64, accuracy: 1e-9)
    }

    func testSquareFormatIsLimitedByShortAxis() {
        let square = FormatCatalog.presets.first { $0.id == "film-66" }!
        let solution = Framing.solve(focalLength: 80, format: square, optics: optics, fill: 0.9)
        XCTAssertEqual(solution.shortFraction, 0.9, accuracy: 1e-9)
        XCTAssertEqual(solution.longFraction, 0.9 * 3 / 4, accuracy: 1e-9)
    }

    func testVeryWideLensIsClippedAtMinimumZoom() {
        let wide = CaptureFormat(id: "617", name: "6×17", width: 168, height: 56, category: .mediumFormatFilm)
        let solution = Framing.solve(focalLength: 35, format: wide, optics: optics)
        XCTAssertEqual(solution.zoom, 1)
        XCTAssertTrue(solution.isClipped)
    }

    func testVeryLongLensStopsAtMaximumZoom() {
        let solution = Framing.solve(focalLength: 1200, format: fullFrame, optics: optics)
        XCTAssertEqual(solution.zoom, 15)
        XCTAssertLessThan(solution.longFraction, 0.85)
    }
}

final class LibraryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testFirstLaunchSeedsStarterKit() {
        let store = LibraryStore(fileURL: fileURL)
        XCTAssertEqual(store.lenses.count, FormatCatalog.starterLenses.count)
        XCTAssertEqual(store.selectedLens?.focalLength, 50)
        XCTAssertEqual(store.selectedFormat.id, FormatCatalog.defaultFormatID)
    }

    func testLensesPersistSortedByFocalLength() {
        let store = LibraryStore(fileURL: fileURL)
        let lens = Lens(name: "Apo-Sironar 40", focalLength: 40)
        store.save(lens)
        store.selectedLensID = lens.id

        let reloaded = LibraryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.lenses.map(\.focalLength), [23, 32, 40, 50, 70])
        XCTAssertEqual(reloaded.selectedLens, lens)
    }

    func testDeletingSelectedLensSelectsNeighbour() {
        let store = LibraryStore(fileURL: fileURL)
        let selected = store.selectedLens!
        store.deleteLens(id: selected.id)
        XCTAssertEqual(store.selectedLens?.focalLength, 70)
    }

    func testLegacyFormatSelectionMovesToSizeGroup() throws {
        let json = #"{"version":1,"lenses":[],"customFormats":[],"selectedFormatID":"hasselblad-cfv-100c"}"#
        try Data(json.utf8).write(to: fileURL)
        let store = LibraryStore(fileURL: fileURL)
        XCTAssertEqual(store.selectedFormat.id, "digital-44x33")
        XCTAssertEqual(store.selectedFormat.longSide, 43.8)
    }

    func testCustomFormatRoundTrip() {
        let store = LibraryStore(fileURL: fileURL)
        let format = CaptureFormat.custom(name: "Cropped 4×5", width: 90, height: 115)
        store.save(format)
        store.selectedFormatID = format.id

        let reloaded = LibraryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.selectedFormat.longSide, 115)
        XCTAssertEqual(reloaded.selectedFormat.shortSide, 90)

        reloaded.deleteFormat(id: format.id)
        XCTAssertEqual(reloaded.selectedFormat.id, FormatCatalog.defaultFormatID)
    }
}

final class ExposureTests: XCTestCase {
    private func index(_ axis: ExposureAxis, _ label: String) -> Int {
        ExposureScale.labels(axis).firstIndex(of: label)!
    }

    func testScalesLineUpWithTheirLabels() {
        XCTAssertEqual(ExposureScale.iso(index(.iso, "100")), 100, accuracy: 1e-9)
        XCTAssertEqual(ExposureScale.iso(index(.iso, "3200")), 3200, accuracy: 20)
        XCTAssertEqual(ExposureScale.aperture(index(.aperture, "8")), 8, accuracy: 1e-9)
        XCTAssertEqual(ExposureScale.aperture(index(.aperture, "22")), 22, accuracy: 0.7)
        XCTAssertEqual(ExposureScale.shutter(index(.shutter, "1\"")), 1, accuracy: 1e-9)
        XCTAssertEqual(ExposureScale.shutter(index(.shutter, "1/125")), 1.0 / 128, accuracy: 1e-9)
        XCTAssertEqual(ExposureScale.shutter(index(.shutter, "30\"")), 32, accuracy: 1e-9)
    }

    func testSunnySixteen() {
        // f/16, 1/125 s, ISO 100 is about EV 15.
        let ev = ExposureSolver.ev100(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                      shutterIndex: index(.shutter, "1/125"))
        XCTAssertEqual(ev, 15, accuracy: 1e-9)
    }

    func testAperturePriorityPicksShutter() {
        let settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: 0, mode: .aperturePriority)
        let solution = ExposureSolver.solve(settings, meteredEV100: 15)
        XCTAssertEqual(solution.label(.shutter), "1/125")
        XCTAssertEqual(solution.meteredAxis, .shutter)
        XCTAssertEqual(solution.exposureError, 0, accuracy: 1e-9)
    }

    func testShutterPriorityPicksAperture() {
        let settings = ExposureSettings(isoIndex: index(.iso, "400"), apertureIndex: 0,
                                        shutterIndex: index(.shutter, "1/125"), mode: .shutterPriority)
        // Two stops more ISO: f/16 becomes f/32.
        let solution = ExposureSolver.solve(settings, meteredEV100: 15)
        XCTAssertEqual(solution.label(.aperture), "f/32")
    }

    func testCompensationBrightens() {
        let settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: 0, mode: .aperturePriority)
        let solution = ExposureSolver.solve(settings, meteredEV100: 15, compensation: 1)
        XCTAssertEqual(solution.label(.shutter), "1/60")
        XCTAssertEqual(solution.exposureError, 1, accuracy: 0.01)
    }

    func testManualReportsOverAndUnderexposure() {
        let settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: index(.shutter, "1/250"), mode: .manual)
        XCTAssertEqual(ExposureSolver.solve(settings, meteredEV100: 15).exposureError, -1, accuracy: 1e-9)
        XCTAssertNil(ExposureSolver.solve(settings, meteredEV100: 15).meteredAxis)
    }

    func testLimitsFlagMeteredValues() {
        let settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: 0, mode: .aperturePriority)
        // Dim light: several seconds, slower than the 1/500–60 s default is fine, but EV 0 needs ~4 min.
        let dim = ExposureSolver.solve(settings, meteredEV100: 0)
        XCTAssertTrue(dim.isOutsideLimits(.shutter, .default))
        let bright = ExposureSolver.solve(settings, meteredEV100: 15)
        XCTAssertFalse(bright.isOutsideLimits(.shutter, .default))
    }

    func testMovingTheMeteredValueSwitchesToManual() {
        var settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: 0, mode: .aperturePriority)
        let solution = ExposureSolver.solve(settings, meteredEV100: 15)
        settings.step(.shutter, by: 1, from: solution)
        XCTAssertEqual(settings.mode, .manual)
        XCTAssertEqual(ExposureScale.label(.shutter, settings.shutterIndex), "1/100")
        XCTAssertEqual(ExposureScale.label(.aperture, settings.apertureIndex), "f/16")

        let manual = ExposureSolver.solve(settings, meteredEV100: 15)
        settings.lock(.shutter, from: manual)
        XCTAssertEqual(settings.mode, .shutterPriority)
        XCTAssertEqual(ExposureScale.label(.shutter, settings.shutterIndex), "1/100")
    }

    func testExposurePersistsWithTheLibrary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("exposure-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(fileURL: url)
        store.exposure.isoIndex = index(.iso, "400")
        store.exposureLimits.shutter = 10...40
        let reloaded = LibraryStore(fileURL: url)
        XCTAssertEqual(reloaded.exposure.isoIndex, index(.iso, "400"))
        XCTAssertEqual(reloaded.exposureLimits.shutter, 10...40)
    }
}
