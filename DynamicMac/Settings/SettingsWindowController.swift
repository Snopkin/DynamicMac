//
//  SettingsWindowController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import SwiftUI

/// Hosts the Settings UI inside an `NSTabViewController` so the tabs render
/// in the window toolbar — the native macOS System Settings look — instead
/// of SwiftUI's `TabView` which draws an unavoidable bezel border.
///
/// Owning the window directly sidesteps the `showSettingsWindow:` deprecation
/// on macOS 14+ and the `LSUIElement` incompatibility with `SettingsLink`.
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

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar

        let tabs: [(String, String, AnyView)] = [
            ("General",    "gearshape",             AnyView(GeneralSettingsTab(settings: settings))),
            ("Appearance", "paintpalette",           AnyView(AppearanceSettingsTab(settings: settings))),
            ("Widgets",    "square.grid.2x2",        AnyView(WidgetsSettingsTab(settings: settings))),
            ("Pomodoro",   "leaf.fill",              AnyView(PomodoroSettingsTab(settings: settings))),
            ("Launcher",   "square.grid.3x3.fill",   AnyView(LauncherSettingsTab(settings: settings, launcher: appLauncherService))),
            ("Clipboard",  "doc.on.clipboard",       AnyView(ClipboardSettingsTab(settings: settings, clipboardService: clipboardService))),
            ("Quick Ask",  "sparkles",               AnyView(QuickAskSettingsTab(settings: settings))),
            ("Media",      "music.note",             AnyView(MediaSettingsTab(settings: settings, mediaService: mediaService))),
            ("About",      "info.circle",            AnyView(AboutSettingsTab())),
        ]

        for (title, icon, view) in tabs {
            let hosting = NSHostingController(rootView: view)
            hosting.title = title
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            tabVC.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabVC)
        window.title = "DynamicMac Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.contentMinSize = NSSize(width: 720, height: 400)
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
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }

        window.makeKeyAndOrderFront(nil)
    }
}
