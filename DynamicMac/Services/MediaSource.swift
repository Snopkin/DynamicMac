//
//  MediaSource.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// Commands that can be sent to the currently-playing app via the
/// media remote stack. Numeric raw values match `MRACommand` in
/// `ungive/mediaremote-adapter`'s `send.m`, so the service layer can
/// pass them straight through without a translation table.
enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

/// Abstraction over the system-wide Now Playing backend.
///
/// The only real implementation today is `MediaRemoteAdapterBridge`,
/// which spawns `ungive/mediaremote-adapter` under `/usr/bin/perl` and
/// streams merged state. Keeping the interface as a protocol means we
/// can swap the backend later (a stub for previews, a sanctioned Apple
/// API if one eventually ships, AppleScript fallbacks for the sandbox).
@MainActor
protocol MediaSource: AnyObject {
    /// Called on every state change. Receives the merged snapshot.
    /// `nil` means "nothing is currently playing".
    var onUpdate: ((NowPlayingInfo?) -> Void)? { get set }

    /// Begin streaming Now Playing updates. Safe to call repeatedly;
    /// subsequent calls are no-ops while already running.
    func start()

    /// Stop streaming and release any spawned helper processes.
    func stop()

    /// Send a playback control command to whatever app owns the
    /// currently-playing session.
    func send(_ command: MediaCommand)
}
