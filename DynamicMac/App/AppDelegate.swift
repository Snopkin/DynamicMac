//
//  AppDelegate.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import Sparkle

/// Lifecycle owner for DynamicMac. Hosts the menu bar status item and
/// the notch island controller. Also owns the app-lifetime services
/// (`TimerService`, `MediaService`, `AppSettings`) so SwiftUI scenes
/// and the island controller can share them through direct references
/// rather than `@Environment` plumbing.
///
/// Sparkle is wired via `SPUStandardUpdaterController`, which boxes up
/// the updater, the user-driver UI, and the delegate. The controller is
/// stored eagerly (`startingUpdater: true`) so the first automatic
/// check fires on its normal schedule without us needing a manual
/// `checkForUpdates()` call. The actual `SUFeedURL` and `SUPublicEDKey`
/// come from Info.plist; see `TECHNICAL_PLAN.md` Phase 5 Part B for
/// the pre-public-release keygen checklist.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    let appSettings = AppSettings()
    private let timerService = TimerService()
    let mediaService = MediaService()
    let powerMonitor = PowerMonitor()
    private lazy var pomodoroService = PomodoroService(settings: appSettings)
    private lazy var appLauncherService = AppLauncherService(settings: appSettings)
    private lazy var islandController = NotchIslandController(
        timerService: timerService,
        mediaService: mediaService,
        appSettings: appSettings,
        powerMonitor: powerMonitor,
        pomodoroService: pomodoroService,
        appLauncherService: appLauncherService
    )
    private lazy var settingsWindowController = SettingsWindowController(
        settings: appSettings,
        mediaService: mediaService,
        appLauncherService: appLauncherService
    )

    /// Sparkle's top-level controller. Started eagerly so Sparkle can
    /// schedule background checks without additional prodding. The
    /// controller owns its own updater and user-driver lifetimes.
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    /// When running under XCUITest (XCTestConfigurationFilePath is set by
    /// the test runner), the island controller's overlay panel interferes
    /// with the UITest runner's window-hierarchy scans and cleanup. Skip
    /// starting it there; the test is only verifying LSUIElement launch.
    private var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        if !isRunningUnderTests {
            // Touching the lazy property boots the Sparkle updater so
            // it can schedule its first background check.
            _ = updaterController
            timerService.restore()
            pomodoroService.restore()
            islandController.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !isRunningUnderTests {
            islandController.shutdown()
            timerService.persistForTermination()
            pomodoroService.persistForTermination()
        }
        powerMonitor.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "oval.fill",
            accessibilityDescription: "DynamicMac"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About DynamicMac",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Sparkle's standard controller exposes `checkForUpdates(_:)` as
        // the canonical menu-item action. Targeting the controller
        // directly lets Sparkle handle enable/disable state on its own
        // (greyed out while a check is in flight, etc.).
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit DynamicMac",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettings() {
        // Delegate to the AppKit-owned settings window. It handles
        // activation-policy flipping, window creation, and the
        // flip-back to `.accessory` when the window closes.
        settingsWindowController.show()
    }

    @objc private func openAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
