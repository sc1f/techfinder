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
