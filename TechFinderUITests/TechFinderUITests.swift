import XCTest

/// Drives the real app in the Simulator. A hang shows up as a failure to find or tap elements.
final class TechFinderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testGridToggleStaysResponsive() {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
