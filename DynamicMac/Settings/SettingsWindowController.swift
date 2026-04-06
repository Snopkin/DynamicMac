//
//  SettingsWindowController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import SwiftUI

/// Hosts `SettingsView` inside a plain `NSWindow`. We used to rely on
/// SwiftUI's `Settings` scene + the `showSettingsWindow:` selector, but
/// on macOS 14+ that path is deprecated and SwiftUI logs
/// "Please use SettingsLink for opening the Settings scene." without
/// actually showing the window under `LSUIElement`. `SettingsLink` only
/// works from a SwiftUI view, so it can't be driven from our AppKit
/// `NSStatusItem` menu.
///
/// Owning the window directly sidesteps both problems: the menu item
/// asks this controller to show itself, the controller flips the
/// activation policy to `.regular`, orders the window front, and
/// registers a `willClose` observer that flips the policy back to
/// `.accessory` so the Dock icon disappears again as soon as the
/// Settings window is dismissed.
@MainActor
final class SettingsWindowController {

    private let settings: AppSettings
    private let mediaService: MediaService
    private let appLauncherService: AppLauncherService
    private let clipboardService: ClipboardService

    private var window: NSWindow?
    private var willCloseObserver: NSObjectProtocol?

    init(
        settings: AppSettings,
        mediaService: MediaService,
        appLauncherService: AppLauncherService,
        clipboardService: ClipboardService
    ) {
        self.settings = settings
        self.mediaService = mediaService
        self.appLauncherService = appLauncherService
        self.clipboardService = clipboardService
    }

    // No deinit: this controller is owned for the app's lifetime by
    // `AppDelegate` (lazy property), so the will-close observer cannot
    // outlive it. Adding a deinit here would force it to be nonisolated,
    // which Swift 6 strict concurrency forbids from touching MainActor
    // state like the stored observer token.

    /// Shows the Settings window, creating it lazily on first call. Safe
    /// to invoke repeatedly — subsequent calls just bring the existing
    /// window to the front.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                mediaService: mediaService,
                appLauncherService: appLauncherService,
                clipboardService: clipboardService
            )
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "DynamicMac Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("DynamicMacSettingsWindow")
        self.window = window

        if let existing = willCloseObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            // Drop back to LSUIElement accessory mode so the Dock icon
            // disappears as soon as the user dismisses Settings. Hop to
            // the main actor explicitly — NotificationCenter's
            // `addObserver(forName:object:queue:using:)` delivers on the
            // given queue but the closure is `@Sendable`, not
            // MainActor-isolated.
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }

        window.makeKeyAndOrderFront(nil)
    }
}
