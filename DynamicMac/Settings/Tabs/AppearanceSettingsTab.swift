//
//  AppearanceSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Appearance preferences: island tint color, reduce-motion status.
///
/// The tint applies to accent elements inside widgets — progress ring
/// stroke, active button glows, selection states. The island body stays
/// black to preserve the seamless-notch illusion on notched displays.
/// Reduce Motion is surfaced read-only because the source of truth is
/// the system accessibility setting, and we already honor it in Phase 1.
struct AppearanceSettingsTab: View {

    @Bindable var settings: AppSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Section("Tint") {
                ColorPicker(
                    "Island accent color",
                    selection: $settings.islandTintColor,
                    supportsOpacity: false
                )
            }

            Section("Motion") {
                HStack {
                    Text("Reduce Motion")
                    Spacer()
                    Text(reduceMotion ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
                Text("Controlled by System Settings → Accessibility → Display → Reduce Motion. When on, DynamicMac swaps the spring for a gentle ease curve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
