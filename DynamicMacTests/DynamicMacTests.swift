//
//  DynamicMacTests.swift
//  DynamicMacTests
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import XCTest
@testable import DynamicMac

/// Phase 0 compile-smoke test. Real unit coverage grows per phase
/// (IslandStateTests in Phase 1, TimerServiceTests in Phase 2, etc.).
final class DynamicMacTests: XCTestCase {

    @MainActor
    func testAppDelegateInstantiates() throws {
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate)
    }
}
