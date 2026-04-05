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

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                iconButton(systemName: "backward.fill") {
                    service.previousTrack()
                }
                iconButton(systemName: playPauseSystemName) {
                    service.togglePlayPause()
                }
                iconButton(systemName: "forward.fill") {
                    service.nextTrack()
                }
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(Constants.Animation.spring, value: service.current?.trackKey)
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
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Buttons

    private var playPauseSystemName: String {
        (service.current?.isPlaying ?? false) ? "pause.fill" : "play.fill"
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
