//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

class TestAppUITests: XCTestCase {
    private enum Timeout {
        static let appLaunch: TimeInterval = 5
        static let webPageLoad: TimeInterval = 15
        static let alertPresentation: TimeInterval = 5
        static let webViewStateUpdate: TimeInterval = 8
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testCompatibilityWrapperLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: Timeout.appLaunch))

        if #available(iOS 17, *) {
            XCTAssert(app.staticTexts["integration-status-active"].waitForExistence(timeout: 5))
        } else {
            XCTAssert(app.staticTexts["integration-status-inactive"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testWebViewAlertAndConfirmHooks() throws {
        guard #available(iOS 17, *) else {
            throw XCTSkip("The study sheet and web view integration are only active on iOS 17 and newer.")
        }

        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: Timeout.appLaunch))
        app.buttons["Test Alert/Confirm"].tap()

        let webView = app.webViews.firstMatch
        let alertStatus = webView.otherElements["Alert Status"]
        let confirmStatus = webView.otherElements["Confirm Status"]

        XCTAssert(alertStatus.staticTexts["Not triggered"].waitForExistence(timeout: Timeout.webPageLoad))

        webView.buttons["Trigger alert()"].tap()
        // ideally we'd also assert that the alert (or confirm) status changes to "active" while presented,
        // but we skip that bc for some reason the web view's contents aren't part of the view hierarchy while the alert/sheet is active.
        XCTAssert(app.alerts.staticTexts["This is the window.alert() test!"].waitForExistence(timeout: Timeout.alertPresentation))
        app.alerts.buttons["OK"].tap()
        XCTAssert(alertStatus.staticTexts["Alert dismissed"].waitForExistence(timeout: Timeout.webViewStateUpdate))

        XCTAssert(confirmStatus.staticTexts["Not triggered"].waitForExistence(timeout: Timeout.webViewStateUpdate))
        webView.buttons["Trigger confirm()"].tap()
        XCTAssert(app.alerts.staticTexts["This is the window.confirm() test!"].waitForExistence(timeout: Timeout.alertPresentation))
        app.alerts.buttons["OK"].tap()
        XCTAssert(confirmStatus.staticTexts["Confirm dismissed; response=true"].waitForExistence(timeout: Timeout.webViewStateUpdate))
        webView.buttons["Trigger confirm()"].tap()
        XCTAssert(app.alerts.staticTexts["This is the window.confirm() test!"].waitForExistence(timeout: Timeout.alertPresentation))
        app.alerts.buttons["Cancel"].tap()
        XCTAssert(confirmStatus.staticTexts["Confirm dismissed; response=false"].waitForExistence(timeout: Timeout.webViewStateUpdate))
    }
}
