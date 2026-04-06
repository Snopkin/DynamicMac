//
//  AppSettings.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// Persisted user preferences backed by `UserDefaults`. Every property
/// reads on init and writes through on mutation, so there is no explicit
/// save step: flipping a toggle in `SettingsView` is immediately visible
/// to anyone observing the same `AppSettings` instance and persists
/// across relaunches.
///
/// The service is injected from `AppDelegate` and passed into
/// `NotchIslandController`, `SettingsView`, and any widget that needs a
/// per-widget toggle. SwiftUI views observe via `@Bindable`, so a change
/// to `islandTintColor` on the Appearance tab updates the expanded island
/// on the next hover without a relaunch.
///
/// Launch-at-Login is wired through `SMAppService.mainApp` (see
/// `LaunchAtLoginController.swift`), which is the macOS 13+ replacement
/// for the old SMLoginItem plist dance. The setter is defensive: if
/// `register()` / `unregister()` throws (e.g. because the app is running
/// from DerivedData during development, or because the user revoked the
/// Background Items permission), it rolls the published value back so
/// the UI reflects reality.
///
/// Persistence helpers, storage keys, and the hex color codec live in
/// `AppSettings+Storage.swift` to keep this file focused on the
/// observable surface area.
@Observable
@MainActor
final class AppSettings {

    /// Injected for tests. Production always uses `UserDefaults.standard`.
    private let defaults: UserDefaults

    /// Injected for tests. Production uses the real `SMAppService`
    /// through `SystemLaunchAtLoginController`.
    private let launchAtLoginController: LaunchAtLoginController

    // MARK: - General

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            // Skip the SMAppService call if we're inside a rollback —
            // the outer didSet already did the persistence write.
            if isRollingBackLaunchAtLogin {
                defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
                return
            }

            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)

            do {
                try launchAtLoginController.setEnabled(launchAtLogin)
            } catch {
                // Roll the published value back so the UI reflects the
                // actual system state instead of our intended state.
                isRollingBackLaunchAtLogin = true
                launchAtLogin = oldValue
                isRollingBackLaunchAtLogin = false
            }
        }
    }

    /// Reentrancy guard for the didSet rollback path above.
    private var isRollingBackLaunchAtLogin = false

    var showIdlePill: Bool {
        didSet {
            guard showIdlePill != oldValue else { return }
            defaults.set(showIdlePill, forKey: Keys.showIdlePill)
        }
    }

    // MARK: - Appearance

    /// User-picked tint applied to the expanded island's accent elements
    /// (progress ring stroke, active button fills, selection glows).
    /// Persisted as a `#RRGGBBAA` hex string so both SwiftUI's `Color` and
    /// AppKit's `NSColor` can reconstruct it without round-tripping
    /// through a catalog.
    var islandTintColor: Color {
        didSet {
            guard !Self.colorsEqual(islandTintColor, oldValue) else { return }
            defaults.set(Self.hex(from: islandTintColor), forKey: Keys.islandTintColor)
        }
    }

    // MARK: - Widgets

    var widgetOrder: [WidgetID] {
        didSet {
            guard widgetOrder != oldValue else { return }
            persistWidgetOrder()
        }
    }

    /// Per-widget on/off state. A widget that is disabled here is hidden
    /// from the expanded island regardless of whether its backing service
    /// has live content.
    var widgetEnabled: [WidgetID: Bool] {
        didSet {
            guard widgetEnabled != oldValue else { return }
            persistWidgetEnabled()
        }
    }

    // MARK: - Media

    /// Master switch for the Now Playing widget. Phase 4 replaces the
    /// "always on" Phase 3 behavior so users can turn it off entirely —
    /// useful if the adapter ever misbehaves on a macOS update.
    var mediaNowPlayingEnabled: Bool {
        didSet {
            guard mediaNowPlayingEnabled != oldValue else { return }
            defaults.set(mediaNowPlayingEnabled, forKey: Keys.mediaNowPlayingEnabled)
        }
    }

    // MARK: - Pomodoro

    /// User-configurable pomodoro parameters (durations, rounds,
    /// auto-start). Live edits from the Pomodoro Settings tab persist
    /// immediately; an in-flight `PomodoroSession` snapshots this at
    /// start time so mid-run edits don't corrupt it.
    var pomodoroConfig: PomodoroConfig {
        didSet {
            guard pomodoroConfig != oldValue else { return }
            if let data = Self.encodePomodoroConfig(pomodoroConfig) {
                defaults.set(data, forKey: Keys.pomodoroConfig)
            }
        }
    }

    // MARK: - Clipboard

    /// Maximum number of unpinned entries kept in the clipboard history.
    var clipboardMaxCount: Int {
        didSet {
            guard clipboardMaxCount != oldValue else { return }
            defaults.set(clipboardMaxCount, forKey: Keys.clipboardMaxCount)
        }
    }

    /// How long unpinned entries are kept before automatic expiry. Zero
    /// means "never expire" — entries are only removed by the count cap.
    var clipboardExpireInterval: TimeInterval {
        didSet {
            guard clipboardExpireInterval != oldValue else { return }
            defaults.set(clipboardExpireInterval, forKey: Keys.clipboardExpireInterval)
        }
    }

    /// Bundle identifiers of apps whose clipboard writes are silently
    /// ignored. Typical use: password managers (1Password, Bitwarden).
    var clipboardIgnoredApps: [String] {
        didSet {
            guard clipboardIgnoredApps != oldValue else { return }
            if let data = try? JSONEncoder().encode(clipboardIgnoredApps) {
                defaults.set(data, forKey: Keys.clipboardIgnoredApps)
            }
        }
    }

    /// When enabled, the pager auto-switches to the Now Playing widget
    /// whenever playback starts. Useful for music-centric users; others
    /// may find the jump disruptive.
    var mediaAutoSwitchOnPlay: Bool {
        didSet {
            guard mediaAutoSwitchOnPlay != oldValue else { return }
            defaults.set(mediaAutoSwitchOnPlay, forKey: Keys.mediaAutoSwitchOnPlay)
        }
    }

    // MARK: - Quick Ask

    /// Whether the user has set their own API key via Settings. This is a
    /// read-through to the Keychain — the actual key never touches
    /// `UserDefaults`. The property triggers observation so SwiftUI views
    /// update when the key changes.
    var quickAskHasUserKey: Bool = AIKeyProvider.hasUserKey

    // MARK: - Launcher

    /// User-picked list of apps pinned to the launcher widget row.
    /// Capped at `launcherEntriesCap` via the encoder/decoder so the
    /// fixed 360pt island content width never overflows.
    var launcherEntries: [AppLauncherEntry] {
        didSet {
            guard launcherEntries != oldValue else { return }
            if let data = Self.encodeLauncherEntries(launcherEntries) {
                defaults.set(data, forKey: Keys.launcherEntries)
            }
        }
    }

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginController: LaunchAtLoginController = SystemLaunchAtLoginController()
    ) {
        self.defaults = defaults
        self.launchAtLoginController = launchAtLoginController

        // Read every key with its documented default. First launch returns
        // the default because `object(forKey:)` is nil, which `?? default`
        // catches cleanly.
        self.launchAtLogin = (defaults.object(forKey: Keys.launchAtLogin) as? Bool) ?? Defaults.launchAtLogin
        self.showIdlePill = (defaults.object(forKey: Keys.showIdlePill) as? Bool) ?? Defaults.showIdlePill
        self.islandTintColor = Self.decodeTintColor(defaults.string(forKey: Keys.islandTintColor))
        self.widgetOrder = Self.decodeWidgetOrder(defaults.array(forKey: Keys.widgetOrder) as? [String])
        self.widgetEnabled = Self.decodeWidgetEnabled(defaults.dictionary(forKey: Keys.widgetEnabled) as? [String: Bool])
        self.mediaNowPlayingEnabled = (defaults.object(forKey: Keys.mediaNowPlayingEnabled) as? Bool) ?? Defaults.mediaNowPlayingEnabled
        self.mediaAutoSwitchOnPlay = (defaults.object(forKey: Keys.mediaAutoSwitchOnPlay) as? Bool) ?? Defaults.mediaAutoSwitchOnPlay
        self.clipboardMaxCount = (defaults.object(forKey: Keys.clipboardMaxCount) as? Int) ?? Defaults.clipboardMaxCount
        self.clipboardExpireInterval = (defaults.object(forKey: Keys.clipboardExpireInterval) as? TimeInterval) ?? Defaults.clipboardExpireInterval
        self.clipboardIgnoredApps = Self.decodeClipboardIgnoredApps(defaults.data(forKey: Keys.clipboardIgnoredApps))
        self.pomodoroConfig = Self.decodePomodoroConfig(defaults.data(forKey: Keys.pomodoroConfig))
        self.launcherEntries = Self.decodeLauncherEntries(defaults.data(forKey: Keys.launcherEntries))

        // Reconcile the persisted launch-at-login toggle with what
        // `SMAppService` actually reports, so the UI never lies: if the
        // user toggled login items off in System Settings, our persisted
        // flag catches up here.
        let systemEnabled = launchAtLoginController.isEnabled
        if systemEnabled != self.launchAtLogin {
            self.launchAtLogin = systemEnabled
        } else if Defaults.launchAtLogin, defaults.object(forKey: Keys.launchAtLogin) == nil {
            // First launch with a default-on toggle: actually register.
            try? launchAtLoginController.setEnabled(true)
        }
    }

    // MARK: - Convenience

    /// Helper used by `IslandRouterView` so the router does not have to
    /// know how widget enable + order interact. Returns the enabled
    /// widgets in the user's chosen priority order.
    /// Enabled widgets in the user's chosen priority order, with all
    /// runtime gates applied. This is the single source of truth used by
    /// both `IslandRouterView` and `NotchIslandController+Scroll` — do
    /// not duplicate this filter elsewhere.
    var enabledWidgetsInPriorityOrder: [WidgetID] {
        widgetOrder.filter { widget in
            guard widgetEnabled[widget] ?? true else { return false }
            if widget == .nowPlaying, !mediaNowPlayingEnabled { return false }
            return true
        }
    }

    /// Returns `true` if the widget is enabled and allowed to render.
    func isEnabled(_ widget: WidgetID) -> Bool {
        widgetEnabled[widget] ?? true
    }

    // MARK: - Persistence helpers

    private func persistWidgetOrder() {
        let rawValues = widgetOrder.map(\.rawValue)
        defaults.set(rawValues, forKey: Keys.widgetOrder)
    }

    private func persistWidgetEnabled() {
        var rawDict: [String: Bool] = [:]
        for (key, value) in widgetEnabled {
            rawDict[key.rawValue] = value
        }
        defaults.set(rawDict, forKey: Keys.widgetEnabled)
    }
}
