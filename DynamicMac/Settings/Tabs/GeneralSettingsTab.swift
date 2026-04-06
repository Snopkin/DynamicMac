//
//  GeneralSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// General preferences: launch-at-login, idle pill visibility.
///
/// Launch-at-login is wired straight to `AppSettings.launchAtLogin`,
/// whose setter calls `SMAppService.mainApp.register()` / `.unregister()`
/// and rolls the UI back if the system rejects the request. Toggling
/// here is therefore honest: the checkbox only stays on if the OS
/// actually accepted the registration.
struct GeneralSettingsTab: View {

    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch DynamicMac at login", isOn: $settings.launchAtLogin)
                Toggle("Show idle pill on non-notched displays", isOn: $settings.showIdlePill)
            } header: {
                Text("Startup")
            } footer: {
                Text("Runs as a menu bar agent — no Dock icon, no window on launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
