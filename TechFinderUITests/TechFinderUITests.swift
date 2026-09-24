import XCTest

/// Drives the real app in the Simulator. A hang shows up as a failure to find or tap elements.
final class TechFinderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testGridToggleStaysResponsive() {
        let app = XCUIApplication.fresh()
        app.launch()

        let grid = app.buttons["gridButton"]
        XCTAssertTrue(grid.waitForExistence(timeout: 15), "Grid button should appear")
        let reset = app.buttons["resetFrameButton"]
        XCTAssertTrue(reset.exists)
        XCTAssertFalse(reset.isEnabled, "Reset is disabled until the frame size changes")

        grid.tap()
        attachScreenshot(of: app, named: "grid-toggled")
        grid.tap()
        XCTAssertTrue(grid.isHittable, "The viewfinder should stay responsive")
    }

    func testLensAndFormatButtonsOpenSheets() {
        let app = XCUIApplication.fresh()
        app.launch()

        let lensButton = app.buttons["lensButton"]
        XCTAssertTrue(lensButton.waitForExistence(timeout: 15))
        lensButton.tap()
        XCTAssertTrue(app.navigationBars["Lenses"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "lenses")
        app.buttons["Done"].firstMatch.tap()

        let formatButton = app.buttons["formatButton"]
        XCTAssertTrue(formatButton.waitForExistence(timeout: 5))
        formatButton.tap()
        XCTAssertTrue(app.navigationBars["Format"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "format")
    }

    func testMeterAndSettings() {
        let app = XCUIApplication.fresh()
        app.launch()

        let shutter = app.otherElements["meter-shutter"].firstMatch
        XCTAssertTrue(shutter.waitForExistence(timeout: 15), "Light meter should appear")
        shutter.tap() // Hold the shutter; the aperture follows the meter.
        attachScreenshot(of: app, named: "meter-shutter-locked")

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "settings")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    /// A 90 mm image circle at f/11 on the 50 mm lens and a 53.4 × 40 back, upright: rise stops where the
    /// top corners meet the circle, and each axis moves on its own.
    func testMovementsStopAtTheImageCircle() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFImageCircle", "90", "-TFMovements", "YES", "-TFRise", "0", "-TFShift", "0",
                               "-TFOverview", "NO"]
        app.launch()

        let dial = app.otherElements["movementDial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 15), "Movement controls should appear")
        XCTAssertEqual(dial.value as? String, "0 mm")

        let up = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        let down = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))

        // Shift first, then rise: each axis moves on its own.
        app.buttons["axis-shift"].tap()
        down.tap()
        XCTAssertEqual(dial.value as? String, "-0.5 mm", "One step shifts half a millimetre")

        app.buttons["axis-rise"].tap()
        XCTAssertEqual(dial.value as? String, "0 mm", "Rise starts at zero")
        for _ in 0..<32 { up.tap() }
        let risen = dial.value as? String ?? ""
        attachScreenshot(of: app, named: "rise-at-limit")
        // At f/8 the f/11 figure is estimated a little smaller; either way rise stops at the image circle,
        // well short of the 25 mm camera limit.
        let millimetres = Double(risen.replacingOccurrences(of: " mm", with: "")) ?? 0
        XCTAssertGreaterThan(millimetres, 10, "Rose to the image circle, got \(risen)")
        XCTAssertLessThan(millimetres, 14, "Stopped at the image circle, got \(risen)")

        app.buttons["axis-shift"].tap()
        XCTAssertEqual(dial.value as? String, "-0.5 mm", "Rising left the shift alone")

        app.buttons["overviewButton"].tap()
        attachScreenshot(of: app, named: "overview")
    }

    func testDraggingTheImageMovesTheChosenAxis() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFImageCircle", "90", "-TFMovements", "YES", "-TFRise", "0", "-TFShift", "0",
                               "-TFOverview", "NO"]
        app.launch()

        let dial = app.otherElements["movementDial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        // In the result view the scene follows the finger: dragging down rises.
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        let value = dial.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("+"), "Dragging down should rise, got \(value)")
    }

    func testLensSelectorTapAndDrag() {
        let app = XCUIApplication.fresh()
        app.launch()

        let lensButton = app.buttons["lensButton"]
        XCTAssertTrue(lensButton.waitForExistence(timeout: 15))

        let thirtyTwo = app.buttons["HR Digaron-S 32"]
        XCTAssertTrue(thirtyTwo.waitForExistence(timeout: 5))
        thirtyTwo.tap()
        XCTAssertTrue(lensButton.label.contains("HR Digaron-S 32"), "Tapping a lens selects it: \(lensButton.label)")

        // Drag from 32 mm across to 70 mm: the glass lens follows the finger and selects on the way.
        let seventy = app.buttons["HR Digaron-S 70"]
        thirtyTwo.press(forDuration: 0.1, thenDragTo: seventy)
        XCTAssertTrue(lensButton.label.contains("HR Digaron-S 70"), "Dragging selects the lens under the finger: \(lensButton.label)")
    }

    func testAddingALensWithAnImageCircle() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFPresent", "newLens"]
        app.launch()

        let focalLength = app.textFields["50"]
        XCTAssertTrue(focalLength.waitForExistence(timeout: 15), "New lens editor should open")
        focalLength.tap()
        focalLength.typeText("72")
        app.buttons["Done"].firstMatch.tap() // Close the number pad.

        app.buttons["Add Image Circle"].tap()
        let diameter = app.textFields["90"]
        if !diameter.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(diameter.waitForExistence(timeout: 5))
        diameter.tap()
        diameter.typeText("158")
        XCTAssertTrue(app.staticTexts["Rise or Fall"].waitForExistence(timeout: 5), "Coverage is shown once a figure is entered")
        // Any number of apertures can be added.
        app.buttons["Done"].firstMatch.tap()
        app.swipeUp()
        app.buttons["Add Another Aperture"].tap()
        app.swipeUp()
        app.buttons["Add Another Aperture"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Add Another Aperture"].exists, "More apertures can still be added")
        attachScreenshot(of: app, named: "lens-image-circle")
        app.buttons["Save"].tap()

        let lensButton = app.buttons["lensButton"]
        XCTAssertTrue(lensButton.waitForExistence(timeout: 5))
        lensButton.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'IC 158 mm'")).firstMatch
            .waitForExistence(timeout: 5), "The library lists the image circle")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIApplication {
    /// The app with an in-memory starter library, so tests don't depend on each other's saved lenses.
    static func fresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-TFFreshLibrary", "YES"]
        return app
    }
}
