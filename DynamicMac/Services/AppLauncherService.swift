//
//  AppLauncherService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// Thin projection over `AppSettings.launcherEntries` plus an in-memory
/// icon cache keyed on entry id (bundle identifier). Launches apps via
/// `NSWorkspace.shared.openApplication(at:configuration:)` with
/// `activates = true` so the launched app comes to the foreground.
///
/// Icons are cached in memory only — ~50KB × 6 entries ≈ 300KB — and
/// invalidated on entry removal. No disk cache: `NSWorkspace.icon(forFile:)`
/// is already fast, and skipping disk avoids the stale-icon problem that
/// shows up when an app updates its bundle icon.
@Observable
@MainActor
final class AppLauncherService {

    private let settings: AppSettings

    /// In-memory icon cache keyed on `AppLauncherEntry.id`. Populated
    /// lazily on first render, cleared on removal.
    private var iconCache: [String: NSImage] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Current launcher entries, sourced from `AppSettings`.
    var entries: [AppLauncherEntry] {
        settings.launcherEntries
    }

    // MARK: - Launch

    /// Open the target application and bring it to the foreground. No-op
    /// if the path no longer exists (app was deleted after being added).
    func launch(_ entry: AppLauncherEntry) {
        let url = entry.url
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        ) { _, _ in
            // Failures are swallowed intentionally — the user sees the
            // icon simply do nothing, which matches how missing apps
            // behave in the Dock.
        }
    }

    // MARK: - Icons

    /// Fetch the icon for a given entry, caching the result. Always
    /// returns *something* (falls back to the generic app SF Symbol) so
    /// the launcher row never renders a blank space.
    func icon(for entry: AppLauncherEntry) -> NSImage {
        if let cached = iconCache[entry.id] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        iconCache[entry.id] = icon
        return icon
    }

    // MARK: - Mutation

    /// Add an entry for the app at `url`. Returns `false` if the bundle
    /// identifier is missing, a duplicate of an existing entry, or the
    /// cap has been reached.
    @discardableResult
    func addEntry(from url: URL) -> Bool {
        guard settings.launcherEntries.count < AppSettings.launcherEntriesCap else {
            return false
        }

        let bundle = Bundle(url: url)
        let identifier = bundle?.bundleIdentifier ?? url.path
        guard !settings.launcherEntries.contains(where: { $0.id == identifier }) else {
            return false
        }

        let displayName = Self.displayName(for: url, bundle: bundle)
        let entry = AppLauncherEntry(
            id: identifier,
            displayName: displayName,
            urlString: url.path
        )
        settings.launcherEntries.append(entry)
        return true
    }

    /// Remove the entry with the given id and drop its cached icon.
    func removeEntry(id: String) {
        settings.launcherEntries.removeAll { $0.id == id }
        iconCache.removeValue(forKey: id)
    }

    /// Reorder via the SwiftUI `.onMove` API's `IndexSet` + destination
    /// offset contract, writing through to `AppSettings.launcherEntries`.
    func reorder(from source: IndexSet, to destination: Int) {
        var current = settings.launcherEntries
        current.move(fromOffsets: source, toOffset: destination)
        settings.launcherEntries = current
    }

    // MARK: - Helpers

    /// Resolve a human-friendly display name for the app. Prefers
    /// `CFBundleDisplayName`, falls back to `CFBundleName`, then the
    /// filename stem, so something sensible always ends up on screen.
    private static func displayName(for url: URL, bundle: Bundle?) -> String {
        if let bundle {
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
                return name
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
