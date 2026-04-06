//
//  SettingsView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Root of the Settings scene hosted by `DynamicMacApp`. Uses a macOS
/// `TabView` with the `.grouped` look the system Settings window adopts
/// under Sequoia/Tahoe. Each tab is a small standalone view so this file
/// stays short and per-tab changes do not force recompiling the shell.
struct SettingsView: View {

    @Bindable var settings: AppSettings
    let mediaService: MediaService
    @Bindable var appLauncherService: AppLauncherService
    @Bindable var clipboardService: ClipboardService

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            WidgetsSettingsTab(settings: settings)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }

            PomodoroSettingsTab(settings: settings)
                .tabItem { Label("Pomodoro", systemImage: "leaf.fill") }

            LauncherSettingsTab(settings: settings, launcher: appLauncherService)
                .tabItem { Label("Launcher", systemImage: "square.grid.3x3.fill") }

            ClipboardSettingsTab(settings: settings, clipboardService: clipboardService)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }

            QuickAskSettingsTab(settings: settings)
                .tabItem { Label("Quick Ask", systemImage: "sparkles") }

            MediaSettingsTab(settings: settings, mediaService: mediaService)
                .tabItem { Label("Media", systemImage: "music.note") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 580, minHeight: 440)
    }
}
