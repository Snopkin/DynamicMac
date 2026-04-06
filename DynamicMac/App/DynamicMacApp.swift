//
//  DynamicMacApp.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// App entry point. The real Settings UI is hosted by
/// `SettingsWindowController` (a plain `NSWindow` + `NSHostingController`)
/// because the SwiftUI `Settings` scene plus the `showSettingsWindow:`
/// selector is deprecated on macOS 14+ and silently fails under
/// `LSUIElement` — SwiftUI logs "Please use SettingsLink for opening
/// the Settings scene." and never shows the window. `SettingsLink` only
/// works from a SwiftUI view, so it can't be driven from our AppKit
/// status-item menu. Owning the window ourselves sidesteps both.
///
/// SwiftUI's `App` protocol still requires at least one `Scene`, so we
/// keep an empty placeholder here. It's never surfaced — nothing ever
/// sends `showSettingsWindow:` against it — so the deprecation warning
/// does not fire.
@main
struct DynamicMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
