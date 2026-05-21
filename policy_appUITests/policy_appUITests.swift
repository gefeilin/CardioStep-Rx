//
//  policy_appUITests.swift
//  policy_appUITests
//
//  Created by Gefei Lin on 5/21/26.
//

import XCTest

final class policy_appUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testNativeDashboardLaunchesAndProfileSheetWorks() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Precision Physical Activity Prescription"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["90-day average"].exists)
        XCTAssertTrue(app.buttons["Edit Profile"].exists)

        app.buttons["Edit Profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit Profile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Generate"].exists)

        app.buttons["Generate"].tap()
        XCTAssertTrue(app.staticTexts["Precision Physical Activity Prescription"].waitForExistence(timeout: 3))

        let quantileButton = app.segmentedControls.buttons["Quantile"]
        XCTAssertTrue(quantileButton.waitForExistence(timeout: 3))
        quantileButton.tap()
        XCTAssertTrue(app.staticTexts["Quantile function of daily steps"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
