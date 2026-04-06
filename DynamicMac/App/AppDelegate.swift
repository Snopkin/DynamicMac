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
    private lazy var clipboardService = ClipboardService(settings: appSettings)
    private lazy var aiService = AIService(settings: appSettings)
    private lazy var islandController = NotchIslandController(
        timerService: timerService,
        mediaService: mediaService,
        appSettings: appSettings,
        powerMonitor: powerMonitor,
        pomodoroService: pomodoroService,
        appLauncherService: appLauncherService,
        clipboardService: clipboardService,
        aiService: aiService
    )
    private lazy var settingsWindowController = SettingsWindowController(
        settings: appSettings,
        mediaService: mediaService,
        appLauncherService: appLauncherService,
        clipboardService: clipboardService
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
            clipboardService.start()
            islandController.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !isRunningUnderTests {
            islandController.shutdown()
            timerService.persistForTermination()
            pomodoroService.persistForTermination()
            clipboardService.persistForTermination()
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
        item.button?.image = makeMenuBarIcon()
        item.menu = buildMenu()
        statusItem = item
    }

    /// Draws the DynamicMac notch-pill icon for the menu bar. Matches the
    /// app icon's central pill shape — a wide rounded rectangle — rendered
    /// as a template image so macOS handles vibrancy and dark/light mode.
    private func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let pillWidth: CGFloat = 14
            let pillHeight: CGFloat = 6
            let cornerRadius: CGFloat = 3
            let pillRect = NSRect(
                x: (bounds.width - pillWidth) / 2,
                y: (bounds.height - pillHeight) / 2,
                width: pillWidth,
                height: pillHeight
            )
            let path = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DynamicMac"
        return image
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
