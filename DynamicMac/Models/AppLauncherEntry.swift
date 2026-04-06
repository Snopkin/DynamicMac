//
//  AppLauncherEntry.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation

/// A single user-picked app that appears as an icon in the App Launcher
/// widget. Persisted inside `AppSettings.launcherEntries` via
/// `AppSettings+Storage`.
///
/// The bundle identifier doubles as the stable `id` — two entries with
/// the same bundle id are considered duplicates and the second add is
/// rejected by `AppLauncherService.addEntry(from:)`. If an app somehow
/// reports a nil bundle id, the launcher falls back to the absolute path.
///
/// The URL is stored as a path string (not a `URL`) because `URL` Codable
/// is verbose, path strings are trivial to inspect in `defaults read`,
/// and a plain string survives the JSON round-trip without scheme / base
/// weirdness.
struct AppLauncherEntry: Codable, Equatable, Identifiable, Hashable {

    /// Stable identifier. Bundle identifier when available, otherwise the
    /// absolute file path as a fallback.
    let id: String

    /// User-facing label shown in Settings and on tooltip hover. Defaults
    /// to the bundle's `CFBundleDisplayName` (or `CFBundleName`, or the
    /// filename stem).
    var displayName: String

    /// Absolute filesystem path to the `.app` bundle, e.g.
    /// `/Applications/Safari.app`.
    var urlString: String

    /// Reconstructed `URL` for launching and icon lookup.
    var url: URL {
        URL(fileURLWithPath: urlString)
    }
}
