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
    }

    func testNoReadingLeavesTheMeteredValueUnset() {
        let settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: index(.shutter, "1/250"), mode: .aperturePriority)
        XCTAssertNil(ExposureSolver.solve(settings, meteredEV100: nil).meteredAxis)
    }

    func testOldManualModeLoadsAsAperturePriority() throws {
        let json = #"{"isoIndex":12,"apertureIndex":18,"shutterIndex":18,"mode":"manual"}"#
        let settings = try JSONDecoder().decode(ExposureSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.mode, .aperturePriority)
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

    func testMovingTheMeteredValueSetsItByHand() {
        var settings = ExposureSettings(isoIndex: index(.iso, "100"), apertureIndex: index(.aperture, "16"),
                                        shutterIndex: 0, mode: .aperturePriority)
        let solution = ExposureSolver.solve(settings, meteredEV100: 15)
        settings.step(.shutter, by: 1, from: solution)
        // The shutter is now set by hand at 1/100 (⅓ stop more light), and the meter closes the aperture ⅓ stop.
        XCTAssertEqual(settings.mode, .shutterPriority)
        XCTAssertEqual(ExposureScale.label(.shutter, settings.shutterIndex), "1/100")
        XCTAssertEqual(ExposureSolver.solve(settings, meteredEV100: 15).label(.aperture), "f/18")

        let shutterPriority = ExposureSolver.solve(settings, meteredEV100: 15)
        settings.lock(.aperture, from: shutterPriority)
        XCTAssertEqual(settings.mode, .aperturePriority)
        XCTAssertEqual(ExposureScale.label(.aperture, settings.apertureIndex), "f/18")
    }

    func testFullStopsLandOnTheStandardSeries() {
        func step(_ axis: ExposureAxis, _ label: String, _ steps: Int) -> String {
            ExposureScale.label(axis, ExposureScale.stepped(index(axis, label), by: steps, thirdsPerStep: 3, axis: axis))
        }
        XCTAssertEqual(step(.iso, "250", 1), "400")
        XCTAssertEqual(step(.iso, "250", -1), "200")
        XCTAssertEqual(step(.iso, "400", 1), "800")
        XCTAssertEqual(step(.iso, "800", 2), "3200")
        XCTAssertEqual(step(.iso, "64", 1), "100")
        XCTAssertEqual(step(.iso, "100", -1), "50")
        XCTAssertEqual(step(.aperture, "9", 1), "f/11")
        XCTAssertEqual(step(.aperture, "8", 1), "f/11")
        XCTAssertEqual(step(.aperture, "5.6", -1), "f/4")
        // Shutter indices run fast to slow: -1 is one stop faster.
        XCTAssertEqual(step(.shutter, "1/100", -1), "1/125")
        XCTAssertEqual(step(.shutter, "1/125", -1), "1/250")
        XCTAssertEqual(step(.shutter, "1/125", 1), "1/60")
        XCTAssertEqual(step(.shutter, "1\"", 1), "2\"")
        // Thirds are plain steps.
        XCTAssertEqual(ExposureScale.label(.iso, ExposureScale.stepped(index(.iso, "250"), by: 1, thirdsPerStep: 1, axis: .iso)), "320")
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

final class ImageCircleTests: XCTestCase {
    func testSingleFigureHoldsWhenStoppedDownAndShrinksWider() {
        let points = [ImageCirclePoint(diameter: 90, fNumber: 11)]
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 16)?.diameter, 90)
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 11)?.isEstimate, false)
        // Two stops wider: 6% smaller, and flagged as an estimate.
        let wide = ImageCircleModel.diameter(points, at: 5.5)!
        XCTAssertEqual(wide.diameter, 90 * 0.94, accuracy: 1e-9)
        XCTAssertTrue(wide.isEstimate)
        // Never below 80% of the figure.
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 1)!.diameter, 72, accuracy: 1e-9)
    }

    func testTwoFiguresInterpolateInStops() {
        let points = [ImageCirclePoint(diameter: 150, fNumber: 22), ImageCirclePoint(diameter: 120, fNumber: 5.6)]
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 5.6)!.diameter, 120, accuracy: 1e-9)
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 22)!.diameter, 150, accuracy: 1e-9)
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 32)!.diameter, 150, accuracy: 1e-9)
        // f/11 is about halfway in stops between f/5.6 and f/22.
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 11)!.diameter, 135, accuracy: 0.5)
    }

    func testSeveralFiguresInterpolateBetweenNeighbours() {
        let points = [ImageCirclePoint(diameter: 120, fNumber: 5.6), ImageCirclePoint(diameter: 150, fNumber: 22),
                      ImageCirclePoint(diameter: 140, fNumber: 11)]
        // f/8 is about halfway (in stops) between f/5.6 and f/11: 120 → 140.
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 8)!.diameter, 130, accuracy: 1)
        // f/16 is halfway between f/11 and f/22: 140 → 150.
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 16)!.diameter, 145, accuracy: 0.5)
    }

    func testRangeOfFiguresNeverShrinksBelowWideOpen() {
        // An 80 mm lens: 80 mm circle wide open at f/4, 90 mm at f/11.
        let points = [ImageCirclePoint(diameter: 80, fNumber: 4), ImageCirclePoint(diameter: 90, fNumber: 11)]
        XCTAssertEqual(ImageCircleModel.diameter(points, at: 2.8), ImageCircleModel.Estimate(diameter: 80, isEstimate: false))
    }

    func testNearestFigureInStops() {
        let points = [ImageCirclePoint(diameter: 80, fNumber: 4), ImageCirclePoint(diameter: 90, fNumber: 11)]
        // f/8 is 0.46 stops from f/11 and 1.0 from f/4.
        XCTAssertEqual(ImageCircleModel.nearest(points, to: 8)?.diameter, 90)
        XCTAssertEqual(ImageCircleModel.nearest(points, to: 5.6)?.diameter, 80)
        XCTAssertEqual(ImageCircleModel.nearest(points, to: 32)?.diameter, 90)
        XCTAssertEqual(ImageCircleModel.nearest(points, to: 2.8)?.diameter, 80)
        // Exactly between (f/6.63): the wider aperture's smaller circle.
        XCTAssertEqual(ImageCircleModel.nearest(points, to: (4.0 * 11.0).squareRoot())?.diameter, 80)
        XCTAssertNil(ImageCircleModel.nearest([], to: 8))
    }

    func testEightyMillimetreExampleAtF11() {
        // 44 × 33 back (43.8 × 32.9) in a 90 mm circle: 20.0 mm along the long side, 22.9 mm along the short.
        let format = FormatCatalog.presets.first { $0.id == "digital-44x33" }!
        let landscape = MovementGeometry(format: format, riseAlongLongSide: false)
        XCTAssertEqual(landscape.maximum(.shift, other: 0, imageCircle: 90, limits: .unlimited), 20.0, accuracy: 0.05)
        XCTAssertEqual(landscape.maximum(.rise, other: 0, imageCircle: 90, limits: .unlimited), 22.9, accuracy: 0.05)
    }

    func testNoFiguresMeansUnknown() {
        XCTAssertNil(ImageCircleModel.diameter([], at: 8))
    }

    func testLensesWithoutImageCircleStillLoad() throws {
        let json = #"{"id":"5A1C4A2E-4B7B-4C8B-9D9A-0F6B7E0B2C11","name":"Old","focalLength":50}"#
        let lens = try JSONDecoder().decode(Lens.self, from: Data(json.utf8))
        XCTAssertEqual(lens.imageCircle, [])
    }
}

final class MovementTests: XCTestCase {
    // 53.4 × 40 back, portrait frame: rise runs along the 53.4 mm side.
    private let geometry = MovementGeometry(format: FormatCatalog.defaultFormat, riseAlongLongSide: true)

    func testUnmovedFrameUsesTheDiagonal() {
        XCTAssertEqual(geometry.farthestCorner(.zero), FormatCatalog.defaultFormat.diagonal / 2, accuracy: 1e-9)
        XCTAssertEqual(geometry.margin(.zero, imageCircle: 90), 45 - 33.36, accuracy: 0.01)
    }

    func testRiseStopsAtTheImageCircle() {
        // 90 mm circle: rise until the top corners touch: sqrt(45² − 20²) − 26.7 ≈ 13.61 mm.
        let maximum = geometry.maximum(.rise, other: 0, imageCircle: 90, limits: .default)
        XCTAssertEqual(maximum, (45.0 * 45 - 20 * 20).squareRoot() - 26.7, accuracy: 1e-9)
        let moved = geometry.moving(.zero, .rise, to: 30, imageCircle: 90, limits: .default)
        XCTAssertEqual(moved.rise, maximum, accuracy: 1e-9)
        XCTAssertEqual(geometry.margin(moved, imageCircle: 90), 0, accuracy: 1e-9)
    }

    func testShiftingFirstLeavesLessRise() {
        let shifted = geometry.moving(.zero, .shift, to: 10, imageCircle: 90, limits: .default)
        XCTAssertEqual(shifted.shift, 10)
        let rise = geometry.maximum(.rise, other: shifted.shift, imageCircle: 90, limits: .default)
        XCTAssertLessThan(rise, geometry.maximum(.rise, other: 0, imageCircle: 90, limits: .default))
    }

    func testIncrementsNeverPassTheLimit() {
        let maximum = geometry.maximum(.rise, other: 0, imageCircle: 90, limits: .default) // ≈ 13.61
        let moved = geometry.moving(.zero, .rise, to: 13.5 + 0.5, imageCircle: 90, limits: .default, increment: 0.5)
        XCTAssertEqual(moved.rise, 13.5)
        XCTAssertLessThanOrEqual(moved.rise, maximum)
        // A corner already on the circle leaves no room, and no negative zero.
        let atEdge = Movement(rise: maximum, shift: 0)
        let blocked = geometry.moving(atEdge, .shift, to: -0.5, imageCircle: 90, limits: .default, increment: 0.5)
        XCTAssertEqual(blocked.shift, 0)
        XCTAssertEqual(blocked.shift.sign, .plus)
    }

    func testMechanicalLimitsApplyWithoutAnImageCircle() {
        let moved = geometry.moving(.zero, .shift, to: -50, imageCircle: nil, limits: .default)
        XCTAssertEqual(moved.shift, -20)
    }

    func testTooSmallACircleAllowsNoMovement() {
        XCTAssertEqual(geometry.maximum(.rise, other: 0, imageCircle: 60, limits: .default), 0)
    }

    func testLayoutPlacesTheMovedFrameOnScreen() {
        let optics = CameraOptics(horizontalFieldOfView: 108.3, aspectRatio: 4.0 / 3.0, minZoom: 1, maxZoom: 15)
        let layout = MovementPlanner.layout(format: FormatCatalog.defaultFormat, focalLength: 50,
                                            movement: Movement(rise: 10, shift: 5), imageCircle: 90,
                                            limits: .default, turnedLeft: nil, optics: optics)
        // Upright: rise moves the frame up the screen (negative y), shift to the right.
        XCTAssertEqual(layout.frameCenterY, -10.0 / 50, accuracy: 1e-9)
        XCTAssertEqual(layout.frameCenterX, 5.0 / 50, accuracy: 1e-9)
        XCTAssertEqual(layout.circleRadius!, 45.0 / 50, accuracy: 1e-9)
        // The whole circle fits the camera image.
        XCTAssertLessThanOrEqual(layout.circleRadius!, layout.imageHalfWidth + 1e-9)
    }

    func testSidewaysPhoneTurnsTheAxes() {
        XCTAssertEqual(MovementPlanner.screenDirections(sideways: true).rise.x, 1)
        XCTAssertEqual(MovementPlanner.screenDirections(sideways: false).rise.x, -1)
    }
}
