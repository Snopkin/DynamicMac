//
//  WidgetID.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// Typed identifier for each widget that can appear inside the expanded
/// island. Drives both `AppSettings.widgetOrder` (user-controlled priority
/// when multiple widgets have live content) and `AppSettings.widgetEnabled`
/// (per-widget on/off toggles in the Settings window).
///
/// Raw values are stable so persisted settings survive app upgrades that
/// reorder the enum. Add new widgets by appending — never renumber. The
/// `decodeWidgetOrder` helper silently drops unknown raw values, so
/// removing a case (like the old `.placeholder` scaffolding) is
/// upgrade-safe: the `missing.append` path injects the new cases at the
/// tail of the order.
enum WidgetID: String, CaseIterable, Identifiable, Codable {
    case timer
    case nowPlaying
    case pomodoro
    case appLauncher

    var id: String { rawValue }

    /// Human-readable label shown in the Widgets settings tab.
    var displayName: String {
        switch self {
        case .timer: return "Timers"
        case .nowPlaying: return "Now Playing"
        case .pomodoro: return "Pomodoro"
        case .appLauncher: return "App Launcher"
        }
    }

    /// Default priority order used on first launch and after a reset.
    /// Pomodoro wins first — a running cycle is the most attention-
    /// demanding state a user has explicitly chosen. Timers are second
    /// for the same reason at lower urgency. Now Playing is ambient
    /// background activity. App Launcher is the idle fallback that
    /// occupies the island when nothing ephemeral is happening.
    static let defaultOrder: [WidgetID] = [.pomodoro, .timer, .nowPlaying, .appLauncher]
}
