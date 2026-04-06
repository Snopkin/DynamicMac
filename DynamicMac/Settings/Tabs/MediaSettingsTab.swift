//
//  MediaSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Media preferences: master switch for Now Playing + adapter status.
///
/// The status line reads `mediaService.current` to show whether the
/// bridge is currently seeing a playing session. It's purely advisory —
/// the underlying adapter restart logic lives in
/// `MediaRemoteAdapterBridge` and keeps running regardless of whether
/// this tab is visible.
struct MediaSettingsTab: View {

    @Bindable var settings: AppSettings
    @Bindable var mediaService: MediaService

    var body: some View {
        Form {
            Section {
                Toggle("Enable Now Playing widget", isOn: $settings.mediaNowPlayingEnabled)
            } header: {
                Text("Now Playing")
            } footer: {
                Text("Shows system-wide playback from Music, Spotify, Safari/Chrome, Podcasts, and other media apps. Turning this off hides the widget entirely, even when something is playing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    Image(systemName: statusIconName)
                        .foregroundStyle(statusIconColor)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        guard settings.mediaNowPlayingEnabled else {
            return "Disabled in settings"
        }
        if let info = mediaService.current, let title = info.title {
            return "Currently playing: \(title)"
        }
        return "Idle — nothing playing"
    }

    private var statusIconName: String {
        guard settings.mediaNowPlayingEnabled else { return "pause.circle" }
        return mediaService.current != nil ? "waveform" : "circle"
    }

    private var statusIconColor: Color {
        guard settings.mediaNowPlayingEnabled else { return .secondary }
        return mediaService.current != nil ? .green : .secondary
    }
}
