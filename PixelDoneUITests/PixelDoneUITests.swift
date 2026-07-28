import XCTest

final class PixelDoneUITests: XCTestCase {
    @MainActor
    func testLaunchAndOpenInspector() throws {
        let app = XCUIApplication()
        app.launch()

        let mainChecklist = app.staticTexts["MAIN"].firstMatch
        XCTAssertTrue(mainChecklist.waitForExistence(timeout: 6))
        mainChecklist.click()

        XCTAssertTrue(
            app.staticTexts["Explore the Apple-native PixelDone"]
                .waitForExistence(timeout: 6)
        )

        let inspect = app.buttons["Inspect"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 4))
        inspect.click()

        XCTAssertTrue(app.staticTexts["TASK"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Edit Task"].exists)
    }
}
