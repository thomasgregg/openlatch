import XCTest

final class OpenLatchUITests: XCTestCase {
    @MainActor func testAppStoreScreenshotCaptures() {
        for language in ["en", "de"] {
            let german = language == "de"
            var app = launch(["-screen", "everyday", "-store-screenshots"], language: language)
            XCTAssertTrue(app.staticTexts[german ? "Verbunden" : "Connected"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts[german ? "Vorschau" : "Preview"].exists)
            capture("Store 01 home - \(language)", app: app)
            app.buttons["otherDoors"].tap()
            capture("Store 02 doors - \(language)", app: app)
            app.terminate()

            app = launch(["-screen", "everyday", "-store-screenshots"], language: language)
            app.buttons[german ? "Einstellungen" : "Settings"].tap()
            app.buttons["manageCars"].tap()
            app.buttons["manage-5YJ3E1EA0LF000000"].tap()
            XCTAssertTrue(app.buttons["defaultDoor"].waitForExistence(timeout: 5))
            capture("Store 03 default - \(language)", app: app)
            app.terminate()

            app = launch(["-screen", "everyday", "-store-screenshots"], language: language)
            app.buttons[german ? "Einstellungen" : "Settings"].tap()
            app.buttons[german ? "Kurzbefehle" : "Shortcuts"].tap()
            XCTAssertTrue(app.staticTexts["Siri"].waitForExistence(timeout: 5))
            capture("Store 04 shortcuts - \(language)", app: app)
            app.terminate()

            app = launch(["-screen", "everyday", "-multi-car", "-store-screenshots"], language: language)
            app.buttons[german ? "Einstellungen" : "Settings"].tap()
            app.buttons["manageCars"].tap()
            XCTAssertTrue(app.buttons["manage-5YJ3E1EA0LF000001"].waitForExistence(timeout: 5))
            capture("Store 05 garage - \(language)", app: app)
            app.terminate()

            app = launch(["-screen", "connect", "-empty-clipboard", "-store-screenshots"], language: language)
            XCTAssertTrue(app.textFields["vinInput"].waitForExistence(timeout: 5))
            capture("Store 06 bluetooth - \(language)", app: app)
            app.terminate()
        }
    }

    @MainActor func testDefaultDoorSettingAndOtherDoorsInBothLanguages() {
        for language in ["en", "de"] {
            let german = language == "de"
            let app = launch(["-screen", "everyday"], language: language)
            XCTAssertTrue(app.staticTexts[german ? "Verbunden" : "Connected"].waitForExistence(timeout: 5))
            app.buttons[german ? "Einstellungen" : "Settings"].tap()
            app.buttons["manageCars"].tap()
            app.buttons["manage-5YJ3E1EA0LF000000"].tap()
            app.buttons["defaultDoor"].tap()
            app.buttons[german ? "Beifahrertür" : "Passenger door"].tap()
            capture("Default door - \(language)", app: app)
            app.buttons[german ? "Fertig" : "Done"].tap()
            let primary = app.buttons[german ? "Beifahrertür öffnen" : "Open passenger door"]
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
            capture("Larger car and default door - \(language)", app: app)
            primary.tap()
            XCTAssertTrue(app.staticTexts[german ? "Tür offen" : "Door open"].waitForExistence(timeout: 5))
            app.buttons["otherDoors"].tap()
            capture("Other doors menu - \(language)", app: app)
            app.buttons[german ? "Tür hinten Fahrerseite öffnen" : "Open rear driver-side door"].tap()
            XCTAssertTrue(app.staticTexts[german ? "Tür offen" : "Door open"].waitForExistence(timeout: 5))
            XCTAssertTrue(primary.exists)
            app.terminate()
        }
    }

    @MainActor func testApprovedModelArtworkScreens() {
        for (name, vin) in [("Model 3", "5YJ3E1EA0LF000000"), ("Model Y", "XP7YGCEK0SB000000"),
                            ("Model S", "7SASA1E20SF000000"), ("Model X", "7SAXCBE20SF000000"),
                            ("Cybertruck", "7G2CEHED0SA000000")] {
            let app = launch(["-screen", "everyday", "-vehicle-vin", vin])
            XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Open driver door"].isHittable)
            capture("Approved artwork - \(name)", app: app)
            app.terminate()
        }
    }

    @MainActor private func launch(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US"] + arguments
        app.launch()
        return app
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor func testFullOnboardingAndCleanMainScreen() {
        let app = launch()
        app.buttons["Connect car"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        XCTAssertFalse(app.buttons["Help"].exists)
        app.buttons["Where’s my VIN?"].tap()
        XCTAssertTrue(app.staticTexts["Tesla app → scroll to the bottom → copy VIN"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let vin = app.textFields["vinInput"]
        vin.tap()
        vin.typeText("5YJ3E1EA0LF000000")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Test door"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["It worked"].isEnabled)
        app.buttons["Test door"].tap()
        XCTAssertTrue(app.staticTexts["Door open"].waitForExistence(timeout: 8))
        app.buttons["It worked"].tap()
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Open driver door"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Shortcut"].exists)
        XCTAssertFalse(app.buttons["Set up Shortcut"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Shortcuts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Help"].exists)
    }

    @MainActor func testInvalidVINCannotPair() {
        let app = launch(["-screen", "connect"])
        let vin = app.textFields["vinInput"]
        vin.tap()
        vin.typeText("INVALID")
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
    }

    @MainActor func testPasteIsHiddenWithAnEmptyClipboard() {
        let app = launch(["-screen", "connect", "-empty-clipboard"])
        let paste = app.buttons["pasteVIN"]
        XCTAssertTrue(app.textFields["vinInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(paste.exists)
        XCTAssertTrue(app.staticTexts["VIN"].exists)
        capture("Empty clipboard - hidden Paste", app: app)
    }

    @MainActor func testPasteNormalizesVINInBothLanguages() {
        for language in ["en", "de"] {
            let app = launch(["-screen", "connect", "-clipboard", "  7g2cehed0sa000000\n"], language: language)
            let paste = app.buttons["pasteVIN"]
            XCTAssertTrue(paste.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[language == "de" ? "Einfügen" : "Paste"].exists)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: paste)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            paste.tap()
            XCTAssertEqual(app.textFields["vinInput"].value as? String, "7G2CEHED0SA000000")
            XCTAssertTrue(app.buttons[language == "de" ? "Weiter" : "Continue"].isEnabled)
            capture("Localized Paste - \(language)", app: app)
            app.terminate()
        }
    }

    @MainActor func testVINCanBeDeletedAndCorrectedManually() {
        let app = launch(["-screen", "connect"])
        let vin = app.textFields["vinInput"]
        vin.tap()
        vin.typeText("5YJ3E1EA0LF000000")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        vin.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertEqual(vin.value as? String, "5YJ3E1EA0LF000")
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        vin.typeText("001")
        XCTAssertEqual(vin.value as? String, "5YJ3E1EA0LF000001")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        vin.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        XCTAssertEqual(vin.value as? String, "Paste your VIN")
    }

    @MainActor func testRecognizingVINDoesNotMoveConnectionControls() {
        let app = launch(["-screen", "connect"])
        let vin = app.textFields["vinInput"]
        vin.tap()
        vin.typeText("5YJ3E1EA0LF00000")
        let fieldBeforeRecognition = vin.frame
        let continueBeforeRecognition = app.buttons["Continue"].frame
        vin.typeText("0")
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        XCTAssertEqual(vin.frame.minY, fieldBeforeRecognition.minY, accuracy: 1)
        XCTAssertEqual(vin.frame.height, fieldBeforeRecognition.height, accuracy: 1)
        XCTAssertEqual(app.buttons["Continue"].frame.minY, continueBeforeRecognition.minY, accuracy: 1)
        XCTAssertEqual(app.buttons["Continue"].frame.height, continueBeforeRecognition.height, accuracy: 1)
    }

    @MainActor func testUnconfirmedResponseIsNotOpen() {
        let app = launch(["-screen", "everyday", "-unconfirmed"])
        let open = app.buttons["Open driver door"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        // Wait for initial foreground connection.
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["Request accepted. Check your door."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Door open"].exists)
    }

    @MainActor func testRemoveKeyReturnsToWelcome() {
        let app = launch(["-screen", "everyday"])
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000000"].tap()
        app.buttons["Remove car"].tap()
        app.alerts.buttons["Remove car"].tap()
        XCTAssertTrue(app.buttons["Connect car"].waitForExistence(timeout: 5))
    }

    @MainActor func testRemoveCarWhileBluetoothReconnectIsPending() {
        let app = launch(["-screen", "everyday", "-slow-connect", "-unavailable"])
        XCTAssertTrue(app.staticTexts["Connecting…"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000000"].tap()
        let remove = app.buttons["Remove car"]
        XCTAssertTrue(remove.isEnabled)
        remove.tap()
        app.alerts.buttons["Remove car"].tap()
        XCTAssertTrue(app.buttons["Connect car"].waitForExistence(timeout: 5))
    }

    @MainActor func testGermanOnboardingAndSettingsFollowSystemLanguage() {
        let app = launch(language: "de")
        XCTAssertTrue(app.buttons["Auto verbinden"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ein Tipp. Tür auf."].exists)
        app.buttons["Auto verbinden"].tap()
        let vin = app.textFields["vinInput"]
        vin.tap()
        vin.typeText("5YJ3E1EA0LF000000")
        app.buttons["Weiter"].tap()
        XCTAssertTrue(app.buttons["Tür testen"].waitForExistence(timeout: 8))
        app.buttons["Tür testen"].tap()
        XCTAssertTrue(app.staticTexts["Tür offen"].waitForExistence(timeout: 8))
        app.buttons["Hat geklappt"].tap()
        app.buttons["Später"].tap()
        XCTAssertTrue(app.buttons["Fahrertür öffnen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.buttons["Kurzbefehle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Autos"].exists)
    }

    @MainActor func testGermanUncertainCommandFeedbackIsLocalized() {
        let app = launch(["-screen", "everyday", "-uncertain"], language: "de")
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        app.buttons["Fahrertür öffnen"].tap()
        XCTAssertTrue(app.staticTexts["Prüfe deine Tür, bevor du es erneut versuchst. Die Anfrage könnte das Auto erreicht haben."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Tür offen"].exists)
    }

    @MainActor func testGermanLargestTextKeepsDoorButtonUsable() {
        let app = launch(["-screen", "everyday", "-unconfirmed",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], language: "de")
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        let open = app.buttons["Fahrertür öffnen"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable)
        open.tap()
        XCTAssertTrue(app.staticTexts["Anfrage bestätigt. Prüfe deine Tür."].waitForExistence(timeout: 5))
    }

    @MainActor func testDoorFeedbackDoesNotMoveTheAction() {
        for language in ["en", "de"] {
            let app = launch(["-screen", "everyday", "-slow-door"], language: language)
            XCTAssertTrue(app.staticTexts[language == "de" ? "Verbunden" : "Connected"].waitForExistence(timeout: 5))
            let open = app.buttons[language == "de" ? "Fahrertür öffnen" : "Open driver door"]
            let original = open.frame
            let otherDoors = app.buttons["otherDoors"]
            let originalOtherDoors = otherDoors.frame
            let before = XCTAttachment(screenshot: app.screenshot())
            before.name = "Before door request"
            before.lifetime = .keepAlways
            add(before)
            open.tap()
            XCTAssertFalse(open.isEnabled)
            XCTAssertEqual(open.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(open.frame.height, original.height, accuracy: 1)
            XCTAssertEqual(otherDoors.frame, originalOtherDoors)
            capture("Door request in progress", app: app)
            let feedback = app.staticTexts[language == "de" ? "Tür offen" : "Door open"]
            XCTAssertTrue(feedback.waitForExistence(timeout: 5))
            XCTAssertEqual(open.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(open.frame.height, original.height, accuracy: 1)
            XCTAssertEqual(otherDoors.frame, originalOtherDoors)
            let after = XCTAttachment(screenshot: app.screenshot())
            after.name = "Door feedback without layout movement"
            after.lifetime = .keepAlways
            add(after)
            let disappears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: feedback)
            XCTAssertEqual(XCTWaiter.wait(for: [disappears], timeout: 9), .completed)
            XCTAssertEqual(open.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(otherDoors.frame, originalOtherDoors)
            app.terminate()
        }
    }

    @MainActor func testCompactGermanSettingsKeepShortcutsAndLicensesAccessible() {
        let app = launch(["-screen", "everyday", "-unconfirmed"], language: "de")
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        app.buttons["Fahrertür öffnen"].tap()
        XCTAssertTrue(app.staticTexts["Anfrage bestätigt. Prüfe deine Tür."].waitForExistence(timeout: 5))
        app.buttons["Einstellungen"].tap()
        XCTAssertFalse(app.staticTexts["Anfrage bestätigt. Prüfe deine Tür."].isHittable)
        XCTAssertFalse(app.buttons["Hilfe"].exists)
        capture("Settings-de", app: app)
        app.buttons["Kurzbefehle"].tap()
        XCTAssertTrue(app.staticTexts["„Öffne meine Fahrertür mit OpenLatch“"].waitForExistence(timeout: 5))
        capture("Shortcuts-de", app: app)
        app.navigationBars["Kurzbefehle"].buttons.element(boundBy: 0).tap()
        app.buttons["Über"].tap()
        capture("About-de", app: app)
        app.buttons["Lizenzen"].tap()
        XCTAssertTrue(app.buttons["TeslaBLE"].waitForExistence(timeout: 5))
        capture("Licenses-de", app: app)
        app.buttons["OpenLatch"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'MIT License'")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testAddSwitchAndRemoveCars() {
        let app = launch(["-screen", "everyday"])
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["Add car"].tap()
        let vin = app.textFields["vinInput"]
        XCTAssertTrue(vin.waitForExistence(timeout: 5))
        vin.tap()
        vin.typeText("5YJ3E1EA0LF000001")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Test door"].waitForExistence(timeout: 8))
        app.buttons["Test door"].tap()
        XCTAssertTrue(app.staticTexts["Door open"].waitForExistence(timeout: 5))
        app.buttons["It worked"].tap()
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000001"].tap()
        app.buttons["renameCar"].tap()
        let name = app.textFields["carNameInput"]
        name.tap()
        let oldName = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + "Bluebird")
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Bluebird"].waitForExistence(timeout: 5))
        capture("Multiple cars main-en", app: app)
        app.buttons["Cars"].tap()
        capture("Car picker-en", app: app)
        XCTAssertTrue(app.buttons["car-5YJ3E1EA0LF000001"].exists)
        app.buttons["car-5YJ3E1EA0LF000000"].tap()
        XCTAssertTrue(app.navigationBars["My Tesla"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000000"].tap()
        app.buttons["Remove car"].tap()
        app.alerts.buttons["Remove car"].tap()
        XCTAssertTrue(app.navigationBars["Bluebird"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cars"].exists)
    }

    @MainActor func testGermanCarPickerAndAddCancellation() {
        let app = launch(["-screen", "everyday", "-multi-car"], language: "de")
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        app.buttons["Autos"].tap()
        XCTAssertTrue(app.buttons["Auto hinzufügen"].exists)
        capture("Car picker-de", app: app)
        app.buttons["car-5YJ3E1EA0LF000001"].tap()
        XCTAssertTrue(app.navigationBars["Bluebird"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
        app.buttons["Einstellungen"].tap()
        XCTAssertFalse(app.buttons["Auto entfernen"].exists)
        XCTAssertFalse(app.staticTexts["Spitzname"].exists)
        capture("Multiple cars settings-de", app: app)
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000001"].tap()
        XCTAssertTrue(app.buttons["Auto entfernen"].exists)
        XCTAssertTrue(app.staticTexts["Autoname"].exists)
        capture("Car details-de", app: app)
        app.navigationBars["Bluebird"].buttons["BackButton"].tap()
        app.buttons["Auto hinzufügen"].tap()
        XCTAssertTrue(app.textFields["vinInput"].waitForExistence(timeout: 5))
        app.buttons["Zurück"].tap()
        XCTAssertTrue(app.navigationBars["Bluebird"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Verbunden"].waitForExistence(timeout: 5))
    }

    @MainActor func testManagingAnotherCarDoesNotChangeSelection() {
        let app = launch(["-screen", "everyday", "-multi-car"])
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["Nickname"].exists)
        XCTAssertFalse(app.buttons["Add car"].exists)
        capture("Clean settings-en", app: app)
        app.buttons["manageCars"].tap()
        capture("Manage cars-en", app: app)
        app.buttons["manage-5YJ3E1EA0LF000001"].tap()
        XCTAssertTrue(app.staticTexts["Car name"].exists)
        XCTAssertTrue(app.buttons["Use this car"].exists)
        capture("Car details-en", app: app)
        app.buttons["renameCar"].tap()
        let field = app.textFields["carNameInput"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Atlas")
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["My Tesla"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["manageCars"].tap()
        app.buttons["manage-5YJ3E1EA0LF000001"].tap()
        XCTAssertTrue(app.navigationBars["Atlas"].waitForExistence(timeout: 5))
        app.buttons["Remove car"].tap()
        app.alerts.buttons["Remove car"].tap()
        XCTAssertTrue(app.navigationBars["My Tesla"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connected"].exists)
    }
}
