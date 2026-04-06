//
//  NowPlayingInfo.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// Snapshot of the current system Now Playing state, derived from the
/// merged payload stream emitted by the `ungive/mediaremote-adapter`
/// Perl helper.
///
/// The adapter's wire contract is newline-delimited JSON where each line
/// is an envelope of the shape `{"type": "data", "diff": bool, "payload": {...}}`.
/// This struct is the merged, consumer-facing view: after applying all
/// received diffs and snapshots, it represents "what is playing right
/// now". See `MediaRemoteAdapterBridge` for the merge implementation.
///
/// An empty `payload` in a `diff: false` envelope signals "nothing is
/// playing right now"; we model that as `NowPlayingInfo?.none` in
/// `MediaService`.
struct NowPlayingInfo: Equatable {

    /// Stable identity for artwork caching and diff detection. Derived
    /// from `(title, artist, album)` since those are the keys the adapter
    /// itself uses for item identity.
    var trackKey: String {
        "\(title ?? "")|\(artist ?? "")|\(album ?? "")"
    }

    var bundleIdentifier: String?

    /// Reserved for future source-attribution UI (e.g. showing which app
    /// is hosting the media session). The adapter already emits this key.
    var parentApplicationBundleIdentifier: String?

    var title: String?
    var artist: String?
    var album: String?

    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var isPlaying: Bool

    /// Base64-encoded artwork bytes exactly as the adapter emits them.
    /// Decoding is deferred to `MediaService` so the hot path (merging
    /// a diff) is not blocked on image work.
    var artworkBase64: String?
    var artworkMimeType: String?
}
