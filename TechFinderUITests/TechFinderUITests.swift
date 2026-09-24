import XCTest

/// Drives the real app in the Simulator. A hang shows up as a failure to find or tap elements.
final class TechFinderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMenuOpensTogglesGridAndStaysResponsive() {
        let app = XCUIApplication()
        app.launch()

        let menu = app.buttons["menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "Menu button should appear")
        menu.tap()

        let grid = app.buttons["Grid"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "Menu should open and show Grid")
        attachScreenshot(of: app, named: "menu-open")

        grid.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isHittable, "The viewfinder should respond after the menu closes")
        attachScreenshot(of: app, named: "menu-closed-grid-toggled")

        // Opening and closing again proves the app is still responsive.
        menu.tap()
        XCTAssertTrue(app.buttons["Grid"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Grid"].firstMatch.tap()
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

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
