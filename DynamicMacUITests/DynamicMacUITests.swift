//
//  DynamicMacUITests.swift
//  DynamicMacUITests
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import XCTest

final class DynamicMacUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAsAgent() throws {
        // DynamicMac is an LSUIElement background agent. Launching should
        // succeed without creating any visible window.
        let app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.windows.firstMatch.exists)
    }
}
