//
//  MediaService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import Foundation
import Observation

/// `@Observable` facade over `MediaSource`. Views bind to `current` and
/// `artworkImage`; everything else (starting the bridge, decoding
/// artwork, sending commands) is called from the view's button actions
/// or from `AppDelegate` lifecycle hooks.
///
/// Artwork is decoded lazily and cached by `trackKey` so a rapid series
/// of elapsed-time diffs on the same track does not re-decode the
/// 200 KB+ base64 blob on every update.
@Observable
@MainActor
final class MediaService {

    /// The currently-playing snapshot, or `nil` when nothing is playing
    /// (or when the backend has not yet emitted its first envelope).
    private(set) var current: NowPlayingInfo?

    /// Decoded artwork for `current`, matched to its `trackKey`. Access
    /// this instead of decoding on the view thread.
    private(set) var artworkImage: NSImage?

    /// Set by `NotchIslandController` so route changes (idle → playing)
    /// can programmatically expand the notch.
    var onPlaybackStateBecameActive: (() -> Void)?

    private let source: MediaSource?
    private var artworkCache: (key: String, image: NSImage)?

    init(source: MediaSource? = MediaRemoteAdapterBridge()) {
        self.source = source
        self.source?.onUpdate = { [weak self] info in
            self?.handleUpdate(info)
        }
    }

    // MARK: - Lifecycle

    func start() {
        source?.start()
    }

    func stop() {
        source?.stop()
    }

    // MARK: - Commands

    func togglePlayPause() { source?.send(.togglePlayPause) }
    func nextTrack() { source?.send(.nextTrack) }
    func previousTrack() { source?.send(.previousTrack) }

    // MARK: - Update handling

    private func handleUpdate(_ info: NowPlayingInfo?) {
        let previousHadTrack = (current != nil)
        current = info

        guard let info else {
            artworkImage = nil
            artworkCache = nil
            return
        }

        refreshArtwork(for: info)

        if !previousHadTrack {
            onPlaybackStateBecameActive?()
        }
    }

    private func refreshArtwork(for info: NowPlayingInfo) {
        let key = info.trackKey

        if let cached = artworkCache, cached.key == key {
            artworkImage = cached.image
            return
        }

        guard
            let base64 = info.artworkBase64,
            let data = Data(base64Encoded: base64),
            let image = NSImage(data: data)
        else {
            artworkImage = nil
            artworkCache = nil
            return
        }

        artworkCache = (key: key, image: image)
        artworkImage = image
    }
}
