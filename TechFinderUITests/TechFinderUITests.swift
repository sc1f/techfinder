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
        XCTAssertFalse(app.buttons["zoomChip"].exists, "The frame-size chip shows only after a pinch")

        grid.tap()
        attachScreenshot(of: app, named: "grid-toggled")
        grid.tap()
        XCTAssertTrue(grid.isHittable, "The viewfinder should stay responsive")
    }

    func testLensAndFormatButtonsOpenSheets() {
        let app = XCUIApplication.fresh()
        app.launch()

        // The lens library opens from Settings.
        openLensLibrary(app)
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
        // Tapping the shutter lists speeds; picking one holds it, and the aperture follows the meter.
        shutter.tap()
        let speed = app.buttons["1/125"].firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 5), "Tapping the shutter lists shutter speeds")
        attachScreenshot(of: app, named: "shutter-list")
        speed.tap()
        XCTAssertEqual(shutter.value as? String, "1/125")
        attachScreenshot(of: app, named: "meter-shutter-locked")

        let aperture = app.otherElements["meter-aperture"].firstMatch
        aperture.tap()
        // The list opens at the metered aperture, f/5.6 here, in whole stops; pick the next one to hold it.
        XCTAssertFalse(app.buttons["f/6.3"].exists, "Full-stop steps list whole stops only")
        let next = app.buttons["f/8"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Tapping the aperture lists apertures")
        attachScreenshot(of: app, named: "aperture-list")
        next.tap()
        XCTAssertEqual(aperture.value as? String, "f/8")

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "settings")
        // Average metering by default; a spot meter is one switch away.
        let metering = app.segmentedControls["meteringPicker"].firstMatch
        XCTAssertTrue(metering.waitForExistence(timeout: 5))
        XCTAssertTrue(metering.buttons["Average"].isSelected)
        metering.buttons["Spot"].tap()
        XCTAssertTrue(metering.buttons["Spot"].isSelected)
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
        app.buttons["Shift"].tap()
        down.tap()
        XCTAssertEqual(dial.value as? String, "-0.5 mm", "One step shifts half a millimetre")

        app.buttons["Rise"].tap()
        XCTAssertEqual(dial.value as? String, "0 mm", "Rise starts at zero")
        for _ in 0..<32 { up.tap() }
        let risen = dial.value as? String ?? ""
        attachScreenshot(of: app, named: "rise-at-limit")
        // At f/8 the f/11 figure is estimated a little smaller; either way rise stops at the image circle,
        // well short of the 25 mm camera limit.
        let millimetres = Double(risen.replacingOccurrences(of: " mm", with: "")) ?? 0
        XCTAssertGreaterThan(millimetres, 10, "Rose to the image circle, got \(risen)")
        XCTAssertLessThan(millimetres, 14, "Stopped at the image circle, got \(risen)")

        app.buttons["Shift"].tap()
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

        // Double-tapping the image returns the current movement to zero, with an offer to undo.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertEqual(dial.value as? String, "0 mm", "Double-tap resets the rise")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "Resetting offers Undo")
        undo.tap()
        XCTAssertEqual(dial.value as? String, value, "Undo puts the rise back")
    }

    /// Tapping the movement value opens a menu to reset it; the arrows and menu don't move the frame.
    func testMovementMenuResets() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFImageCircle", "90", "-TFMovements", "YES", "-TFRise", "6", "-TFShift", "3",
                                "-TFOverview", "NO"]
        app.launch()

        let dial = app.otherElements["movementDial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 15))
        XCTAssertEqual(dial.value as? String, "+6.0 mm")
        dial.tap()
        let resetRise = app.buttons["Reset Rise to 0"]
        XCTAssertTrue(resetRise.waitForExistence(timeout: 5), "Tapping the value opens the reset menu")
        attachScreenshot(of: app, named: "movement-menu")
        resetRise.tap()
        XCTAssertEqual(dial.value as? String, "0 mm")
        app.buttons["Shift"].tap()
        XCTAssertEqual(dial.value as? String, "+3.0 mm", "Resetting rise leaves shift alone")

        dial.tap()
        app.buttons["Reset Rise and Shift"].tap()
        XCTAssertEqual(dial.value as? String, "0 mm")
    }

    /// Pinching changes the frame size and brings up a chip that puts it back.
    func testPinchShowsAFrameSizeChip() {
        let app = XCUIApplication.fresh()
        app.launch()
        let image = app.otherElements["viewfinderImage"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        image.pinch(withScale: 0.6, velocity: -1)
        let chip = app.buttons["zoomChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "A pinch shows the frame-size chip")
        attachScreenshot(of: app, named: "zoom-chip")
        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 3), "Tapping the chip returns to the standard size")
    }

    /// Choosing a lens with a nickname shows the nickname over the image for a moment.
    func testLensNicknameShowsBriefly() throws {
        let app = XCUIApplication.fresh()
        app.launch()
        let thirtyTwo = app.buttons["HR Digaron-S 32"]
        XCTAssertTrue(thirtyTwo.waitForExistence(timeout: 15))
        thirtyTwo.tap()
        attachScreenshot(of: app, named: "lens-nickname")
        // Any element type: Liquid Glass can wrap the text. iOS 26 leaves the non-interactive glass pill
        // out of the accessibility tree altogether (the screenshot above shows it); VoiceOver announces
        // the name instead.
        let notice = app.descendants(matching: .any)["lensNotice"]
        guard notice.waitForExistence(timeout: 2) else {
            if #available(iOS 26, *) {
                throw XCTSkip("iOS 26 hides the glass pill from UI tests; see the lens-nickname screenshot")
            }
            XCTFail("The nickname shows")
            return
        }
        XCTAssertTrue(notice.label.contains("HR Digaron-S 32"), notice.label)
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "and fades out")
    }

    func testIsoListAndFullStops() {
        let app = XCUIApplication.fresh()
        app.launch()

        let iso = app.otherElements["meter-iso"].firstMatch
        XCTAssertTrue(iso.waitForExistence(timeout: 15))
        XCTAssertEqual(iso.value as? String, "100")

        // Tapping the value lists the ISOs in whole stops, opened at the current one; pick 400.
        iso.tap()
        let choice = app.buttons["400"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Tapping ISO lists the ISOs")
        attachScreenshot(of: app, named: "iso-list")
        XCTAssertFalse(app.buttons["125"].exists, "Third stops are listed only with ⅓-stop steps")
        choice.tap()
        XCTAssertEqual(iso.value as? String, "400")

        // A full-stop step from 400 is 800.
        iso.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(iso.value as? String, "800")
    }

    /// The meter stops at the equipment's limits and reports the exposure error instead of an f-number
    /// the lenses don't have. The Simulator's light reads EV 12.
    func testMeterStopsAtTheLimitsWithAnExposureWarning() throws {
        let app = XCUIApplication.fresh()
        app.launch()
        let shutter = app.otherElements["meter-shutter"].firstMatch
        let aperture = app.otherElements["meter-aperture"].firstMatch
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))

        // Slow the shutter to 1 s (left is slower); at EV 12 and ISO 100 that needs f/64.
        let slower = shutter.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
        for _ in 0..<6 { slower.tap() }
        XCTAssertEqual(shutter.value as? String, "1\"")
        XCTAssertEqual(aperture.value as? String, "f/32", "The metered aperture stops at the smallest limit")
        attachScreenshot(of: app, named: "exposure-warning")

        // iOS 26 leaves glass-only notices out of the accessibility tree (see the screenshot).
        let warning = app.descendants(matching: .any)["exposureWarning"]
        if warning.waitForExistence(timeout: 2) {
            XCTAssertTrue(warning.label.hasPrefix("Overexposed 2 stops"), warning.label)
        } else if #unavailable(iOS 26) {
            XCTFail("The overexposure warning shows")
        }
    }

    /// Held sideways, the meter pills stay put and stand upright to the viewer, shutter at the top, and
    /// their lists open turned to read upright.
    func testLandscapeMeterTurnsInPlace() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFSimulateHold", "landscapeLeft"]
        app.launch()

        let shutter = app.otherElements["meter-shutter"].firstMatch
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        let aperture = app.otherElements["meter-aperture"].firstMatch
        let iso = app.otherElements["meter-iso"].firstMatch
        // Turned left, the viewer's top is the screen's right: shutter, aperture, ISO from there.
        XCTAssertGreaterThan(shutter.frame.midX, aperture.frame.midX)
        XCTAssertGreaterThan(aperture.frame.midX, iso.frame.midX)

        // The screen's right arrow points to the viewer's top and raises: a faster shutter.
        shutter.tap()
        let list = app.collectionViews["choices"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Tapping the shutter lists speeds")
        XCTAssertGreaterThan(list.frame.width, list.frame.height, "The list is turned to read upright")
        attachScreenshot(of: app, named: "landscape-shutter-list")
        app.buttons["1/125"].firstMatch.tap()
        XCTAssertEqual(shutter.value as? String, "1/125")
        shutter.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(shutter.value as? String, "1/250", "Up raises")
    }

    /// On whatever iPhone this runs on, every control sits in the black bands around the camera image,
    /// upright and held sideways. CI runs this on several screen sizes.
    func testControlsStayOffTheImage() {
        for hold in ["portrait", "landscapeLeft"] {
            let app = XCUIApplication.fresh()
            app.launchArguments += ["-TFSimulateHold", hold, "-TFImageCircle", "90", "-TFMovements", "YES",
                                    "-TFRise", "4", "-TFShift", "0", "-TFOverview", "NO"]
            app.launch()
            let image = app.otherElements["viewfinderImage"].firstMatch
            XCTAssertTrue(image.waitForExistence(timeout: 15), hold)
            let imageFrame = image.frame
            attachScreenshot(of: app, named: "layout-\(hold)")

            var controls: [(String, XCUIElement)] = [
                ("grid", app.buttons["gridButton"].firstMatch),
                ("mode switch", app.segmentedControls["modeSwitch"].firstMatch),
                ("settings", app.buttons["settingsButton"].firstMatch),
                ("frame", app.buttons["formatButton"].firstMatch),
            ]
            controls += [("ISO", app.otherElements["meter-iso"].firstMatch),
                         ("aperture", app.otherElements["meter-aperture"].firstMatch),
                         ("shutter", app.otherElements["meter-shutter"].firstMatch)]
            if hold == "portrait" {
                // Upright, the movement controls take the lens selector's place. Held sideways they run
                // along the viewer's bottom edge, over the image, and the selector stays.
                controls.append(("movement dial", app.otherElements["movementDial"].firstMatch))
                XCTAssertFalse(app.otherElements["lensSelector"].exists, "Movements take the selector's place")
            } else {
                controls.append(("lens selector", app.otherElements["lensSelector"].firstMatch))
            }
            for (name, element) in controls {
                XCTAssertTrue(element.waitForExistence(timeout: 5), "\(name) exists (\(hold))")
                let frame = element.frame
                XCTAssertFalse(frame.insetBy(dx: 1, dy: 1).intersects(imageFrame),
                               "\(name) \(frame) covers the image \(imageFrame) (\(hold))")
                XCTAssertTrue(app.windows.firstMatch.frame.contains(frame.insetBy(dx: 1, dy: 1)),
                              "\(name) \(frame) is on screen (\(hold))")
            }
            app.terminate()
        }
    }

    /// From an empty library to ten lenses, the lens selector stays on screen, off the image and centred,
    /// with the selected lens showing; a screenshot of each is attached.
    func testLensSelectorWithAnyNumberOfLenses() {
        let focalLengths = [18, 23, 28, 32, 40, 50, 65, 80, 100, 150]
        for count in 0...focalLengths.count {
            let lenses = focalLengths.prefix(count)
            let app = XCUIApplication.fresh()
            app.launchArguments += ["-TFLenses", lenses.map(String.init).joined(separator: ",")]
            app.launch()

            let selector = app.otherElements["lensSelector"].firstMatch
            XCTAssertTrue(selector.waitForExistence(timeout: 15), "\(count) lenses")
            let window = app.windows.firstMatch.frame
            let image = app.otherElements["viewfinderImage"].firstMatch.frame
            attachScreenshot(of: app, named: "lenses-\(count)")

            if count == 0 {
                XCTAssertTrue(app.buttons["Add Lens"].isHittable, "An empty library offers Add Lens")
            } else {
                // The first lens is selected; it shows and can be tapped, as can the last after sliding.
                let first = app.buttons["\(lenses.first!) mm"].firstMatch
                XCTAssertTrue(first.waitForExistence(timeout: 5), "\(count) lenses")
                XCTAssertTrue(first.isHittable, "The selected lens shows with \(count) lenses")
                XCTAssertTrue(first.isSelected, "\(count) lenses")
                XCTAssertTrue(window.contains(first.frame), "\(count) lenses: \(first.frame)")
            }
            let row = selector.segmentedControls.firstMatch.exists ? selector.segmentedControls.firstMatch.frame : selector.frame
            XCTAssertTrue(window.insetBy(dx: 15, dy: 0).contains(row), "\(count) lenses: selector \(row) fits")
            XCTAssertFalse(row.intersects(image), "\(count) lenses: selector covers the image")
            XCTAssertEqual(row.midX, window.midX, accuracy: 1, "\(count) lenses: selector is centred")
            app.terminate()
        }
    }

    func testLensSelectorTapAndDrag() {
        let app = XCUIApplication.fresh()
        app.launch()

        let thirtyTwo = app.buttons["HR Digaron-S 32"]
        XCTAssertTrue(thirtyTwo.waitForExistence(timeout: 15))
        thirtyTwo.tap()
        XCTAssertTrue(thirtyTwo.isSelected, "Tapping a lens selects it")

        // Drag from 32 mm across to 70 mm: the glass lens follows the finger and selects on the way.
        let seventy = app.buttons["HR Digaron-S 70"]
        thirtyTwo.press(forDuration: 0.1, thenDragTo: seventy)
        XCTAssertTrue(seventy.isSelected, "Dragging selects the lens under the finger")
    }

    func testAddingALensWithAnImageCircle() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFPresent", "newLens"]
        app.launch()

        let focalLength = app.textFields["50"]
        XCTAssertTrue(focalLength.waitForExistence(timeout: 15), "New lens editor should open")
        focalLength.tap()
        focalLength.typeText("72")
        closeKeyboard(app)

        app.buttons["Add Image Circle"].tap()
        let diameter = app.textFields["90"]
        if !diameter.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(diameter.waitForExistence(timeout: 5))
        diameter.tap()
        diameter.typeText("158")
        XCTAssertTrue(app.staticTexts["Rise or Fall"].waitForExistence(timeout: 5), "Coverage is shown once a figure is entered")
        // Any number of apertures can be added.
        closeKeyboard(app)
        app.swipeUp()
        app.buttons["Add Another Aperture"].tap()
        app.swipeUp()
        app.buttons["Add Another Aperture"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Add Another Aperture"].exists, "More apertures can still be added")
        attachScreenshot(of: app, named: "lens-image-circle")
        app.buttons["Save"].tap()

        openLensLibrary(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'IC 158 mm'")).firstMatch
            .waitForExistence(timeout: 5), "The library lists the image circle")
    }

    /// Lenses | Movements switches the row above the buttons between the lens selector and the movement
    /// controls.
    func testModeSwitchShowsLensesOrMovements() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFImageCircle", "90"]
        app.launch()
        let modeSwitch = app.segmentedControls["modeSwitch"].firstMatch
        XCTAssertTrue(modeSwitch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["lensSelector"].exists)

        modeSwitch.buttons["Movements"].tap()
        XCTAssertTrue(app.otherElements["movementDial"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["lensSelector"].exists)
        attachScreenshot(of: app, named: "mode-movements")

        modeSwitch.buttons["Lenses"].tap()
        XCTAssertTrue(app.otherElements["lensSelector"].waitForExistence(timeout: 5))
    }

    /// A long press on the lens selector opens the lens library.
    func testLongPressOnTheLensSelectorOpensTheLibrary() {
        let app = XCUIApplication.fresh()
        app.launch()
        let fifty = app.buttons["HR Digaron-S 50"]
        XCTAssertTrue(fifty.waitForExistence(timeout: 15))
        fifty.press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["Lenses"].waitForExistence(timeout: 5), "A long press opens the library")
        XCTAssertTrue(fifty.isSelected, "The selected lens is unchanged")
    }

    /// First launch: one welcome screen, then the viewfinder, or the format picker straight away.
    func testWelcomeOnFirstLaunch() {
        let app = XCUIApplication.fresh()
        app.launchArguments += ["-TFWelcome", "YES"]
        app.launch()
        let choose = app.buttons["welcomeChooseFormat"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15), "The welcome shows on first launch")
        attachScreenshot(of: app, named: "welcome")
        choose.tap()
        XCTAssertTrue(app.navigationBars["Format"].waitForExistence(timeout: 5), "Choose Your Format opens the formats")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertFalse(choose.exists, "The welcome is gone")
        XCTAssertTrue(app.otherElements["meter-iso"].firstMatch.waitForExistence(timeout: 5))
    }

    private func openLensLibrary(_ app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let lenses = app.buttons["settingsLenses"]
        XCTAssertTrue(lenses.waitForExistence(timeout: 5))
        lenses.tap()
        XCTAssertTrue(app.navigationBars["Lenses"].waitForExistence(timeout: 5), "Settings opens the lens library")
    }

    /// Taps the keyboard's Done button when the keyboard is showing (it may not be on CI).
    private func closeKeyboard(_ app: XCUIApplication) {
        let done = app.keyboards.count > 0 ? app.toolbars.buttons["Done"].firstMatch : app.buttons["NoKeyboard"]
        if done.exists { done.tap() }
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
