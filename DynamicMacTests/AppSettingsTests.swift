//
//  AppSettingsTests.swift
//  DynamicMacTests
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI
import XCTest
@testable import DynamicMac

/// Exercises the persistence contract for `AppSettings` and the
/// rollback behavior of the launch-at-login setter. Uses a suite-backed
/// `UserDefaults` so the real standard defaults are never touched.
@MainActor
final class AppSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var launchController: FakeLaunchAtLoginController!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "DynamicMacTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        launchController = FakeLaunchAtLoginController()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        launchController = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testFirstLaunchUsesDefaults() {
        let settings = makeSettings()

        XCTAssertTrue(settings.launchAtLogin, "Default should be on per product decision")
        XCTAssertFalse(settings.showIdlePill)
        XCTAssertTrue(settings.mediaNowPlayingEnabled)
        XCTAssertEqual(settings.widgetOrder, WidgetID.defaultOrder)
        for widget in WidgetID.allCases {
            XCTAssertTrue(settings.isEnabled(widget))
        }
    }

    func testFirstLaunchRegistersLaunchItemWhenDefaultOn() {
        _ = makeSettings()
        XCTAssertTrue(launchController.isEnabled,
                      "Default-on launch-at-login should auto-register on first boot")
    }

    // MARK: - Persistence round-trip

    func testTogglesRoundTrip() {
        do {
            let settings = makeSettings()
            settings.showIdlePill = true
            settings.mediaNowPlayingEnabled = false
        }
        let reloaded = makeSettings()
        XCTAssertTrue(reloaded.showIdlePill)
        XCTAssertFalse(reloaded.mediaNowPlayingEnabled)
    }

    func testTintColorRoundTrip() {
        let expected = Color(.sRGB, red: 0.2, green: 0.6, blue: 0.9, opacity: 1.0)
        do {
            let settings = makeSettings()
            settings.islandTintColor = expected
        }
        let reloaded = makeSettings()
        // We can't compare `Color` values directly across init; round-trip
        // through the same hex encoder that `AppSettings` uses internally.
        let lhs = NSColor(reloaded.islandTintColor).usingColorSpace(.sRGB)
        let rhs = NSColor(expected).usingColorSpace(.sRGB)
        XCTAssertEqual(lhs?.redComponent ?? 0, rhs?.redComponent ?? 0, accuracy: 0.01)
        XCTAssertEqual(lhs?.greenComponent ?? 0, rhs?.greenComponent ?? 0, accuracy: 0.01)
        XCTAssertEqual(lhs?.blueComponent ?? 0, rhs?.blueComponent ?? 0, accuracy: 0.01)
    }

    // MARK: - Widget order

    func testWidgetOrderMutationPersists() {
        do {
            let settings = makeSettings()
            settings.widgetOrder = [.nowPlaying, .timer, .appLauncher, .pomodoro]
        }
        let reloaded = makeSettings()
        XCTAssertEqual(reloaded.widgetOrder, [.nowPlaying, .timer, .appLauncher, .pomodoro])
    }

    func testWidgetEnabledMutationPersists() {
        do {
            let settings = makeSettings()
            settings.widgetEnabled[.appLauncher] = false
        }
        let reloaded = makeSettings()
        XCTAssertFalse(reloaded.isEnabled(.appLauncher))
        XCTAssertTrue(reloaded.isEnabled(.timer))
        XCTAssertTrue(reloaded.isEnabled(.nowPlaying))
        XCTAssertTrue(reloaded.isEnabled(.pomodoro))
    }

    func testEnabledWidgetsInPriorityOrderRespectsBothFields() {
        let settings = makeSettings()
        settings.widgetOrder = [.nowPlaying, .timer, .appLauncher, .pomodoro]
        settings.widgetEnabled[.timer] = false

        XCTAssertEqual(
            settings.enabledWidgetsInPriorityOrder,
            [.nowPlaying, .appLauncher, .pomodoro]
        )
    }

    // MARK: - Launch-at-login rollback

    func testLaunchAtLoginRollbackOnControllerFailure() {
        let settings = makeSettings()
        XCTAssertTrue(settings.launchAtLogin)

        // First launch already registered the fake with `true`. Now tell
        // it to reject the next `setEnabled(false)` call and verify the
        // setter rolls the observable value back to `true`.
        launchController.shouldThrowOnNextCall = true
        settings.launchAtLogin = false

        XCTAssertTrue(settings.launchAtLogin,
                      "Rollback should leave the published flag at its previous value")
        XCTAssertTrue(launchController.isEnabled,
                      "A failed unregister should leave the underlying controller state untouched")
    }

    // MARK: - Future-proofing

    func testMigrationFillsInNewWidgetsFromPersistedOrder() {
        // Simulate a persisted order missing the two new widgets (e.g.
        // saved by a build that only knew about timer + nowPlaying). The
        // loader must append missing widgets so the user never ends up
        // with an incomplete list.
        defaults.set(["timer", "nowPlaying"], forKey: AppSettings.Keys.widgetOrder)
        let settings = makeSettings()
        XCTAssertTrue(settings.widgetOrder.contains(.pomodoro))
        XCTAssertTrue(settings.widgetOrder.contains(.appLauncher))
        XCTAssertEqual(settings.widgetOrder.prefix(2), [.timer, .nowPlaying])
    }

    func testLegacyPlaceholderRawValueDropped() {
        // Users upgrading from a build that persisted the old
        // `.placeholder` case must have that stray raw value silently
        // stripped (compactMap + WidgetID.init(rawValue:) returns nil),
        // and the two new widgets must be injected at the tail.
        defaults.set(["timer", "nowPlaying", "placeholder"], forKey: AppSettings.Keys.widgetOrder)
        let settings = makeSettings()
        let rawValues = settings.widgetOrder.map(\.rawValue)
        XCTAssertFalse(rawValues.contains("placeholder"))
        XCTAssertTrue(settings.widgetOrder.contains(.pomodoro))
        XCTAssertTrue(settings.widgetOrder.contains(.appLauncher))
    }

    // MARK: - Pomodoro

    func testPomodoroConfigDefaultsOnFirstLaunch() {
        let settings = makeSettings()
        XCTAssertEqual(settings.pomodoroConfig, PomodoroConfig.default)
    }

    func testPomodoroConfigRoundTrip() {
        do {
            let settings = makeSettings()
            var edited = settings.pomodoroConfig
            edited.focusDuration = 30 * 60
            edited.shortBreakDuration = 7 * 60
            edited.roundsBeforeLongBreak = 3
            edited.autoStartNextPhase = false
            settings.pomodoroConfig = edited
        }
        let reloaded = makeSettings()
        XCTAssertEqual(reloaded.pomodoroConfig.focusDuration, 30 * 60)
        XCTAssertEqual(reloaded.pomodoroConfig.shortBreakDuration, 7 * 60)
        XCTAssertEqual(reloaded.pomodoroConfig.roundsBeforeLongBreak, 3)
        XCTAssertFalse(reloaded.pomodoroConfig.autoStartNextPhase)
    }

    // MARK: - Launcher entries

    func testLauncherEntriesDefaultEmpty() {
        let settings = makeSettings()
        XCTAssertTrue(settings.launcherEntries.isEmpty)
    }

    func testLauncherEntriesRoundTrip() {
        let entry = AppLauncherEntry(
            id: "com.apple.Safari",
            displayName: "Safari",
            urlString: "/Applications/Safari.app"
        )
        do {
            let settings = makeSettings()
            settings.launcherEntries = [entry]
        }
        let reloaded = makeSettings()
        XCTAssertEqual(reloaded.launcherEntries, [entry])
    }

    func testLauncherEntriesCapEnforcedOnDecode() {
        // Hand-encode 10 entries straight into the backing store, bypassing
        // the didSet setter, to simulate a corrupted or hand-edited plist.
        let oversized = (0..<10).map { idx in
            AppLauncherEntry(
                id: "com.example.app\(idx)",
                displayName: "App \(idx)",
                urlString: "/Applications/App\(idx).app"
            )
        }
        let data = try? JSONEncoder().encode(oversized)
        XCTAssertNotNil(data)
        defaults.set(data, forKey: AppSettings.Keys.launcherEntries)

        let settings = makeSettings()
        XCTAssertLessThanOrEqual(settings.launcherEntries.count, 6)
    }

    // MARK: - Helpers

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: defaults, launchAtLoginController: launchController)
    }
}

// MARK: - Fake

/// Test double for `LaunchAtLoginController` that records state in
/// memory so we never touch the real `SMAppService`.
@MainActor
private final class FakeLaunchAtLoginController: LaunchAtLoginController {

    private(set) var isEnabled: Bool = false
    var shouldThrowOnNextCall: Bool = false

    struct RejectedError: Error {}

    func setEnabled(_ enabled: Bool) throws {
        if shouldThrowOnNextCall {
            shouldThrowOnNextCall = false
            throw RejectedError()
        }
        isEnabled = enabled
    }
}
