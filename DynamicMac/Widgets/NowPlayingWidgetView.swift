//
//  NowPlayingWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Expanded-island UI for system-wide Now Playing. Shows album artwork,
/// track metadata, and transport controls. The service handles artwork
/// decode and caching so this view only ever reads ready-made values.
struct NowPlayingWidgetView: View {

    @Bindable var service: MediaService

    /// Resolved transition animation passed in from `IslandRouterView`,
    /// already folding Reduce Motion + Low Power Mode into the decision.
    let animation: SwiftUI.Animation

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(service.current?.title ?? "Nothing playing")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(service.current?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibleTrackDescription)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                iconButton(systemName: "backward.fill", accessibilityLabel: "Previous track") {
                    service.previousTrack()
                }
                iconButton(
                    systemName: playPauseSystemName,
                    accessibilityLabel: (service.current?.isPlaying ?? false) ? "Pause" : "Play"
                ) {
                    service.togglePlayPause()
                }
                iconButton(systemName: "forward.fill", accessibilityLabel: "Next track") {
                    service.nextTrack()
                }
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(animation, value: service.current?.trackKey)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = service.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Buttons

    private var playPauseSystemName: String {
        (service.current?.isPlaying ?? false) ? "pause.fill" : "play.fill"
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Accessibility helpers

    private var accessibleTrackDescription: String {
        guard let info = service.current, let title = info.title else {
            return "Nothing playing"
        }
        if let artist = info.artist, !artist.isEmpty {
            return "\(title) by \(artist)"
        }
        return title
    }
}
