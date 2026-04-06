//
//  AppSettings+Storage.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import Foundation
import os
import SwiftUI

/// Keys, defaults, and persistence helpers for `AppSettings`. Split from
/// the main file to keep the observable class under the 250-line soft cap.
extension AppSettings {

    /// `UserDefaults` keys for every persisted setting. Strings live in
    /// one place so there is zero risk of a typo causing a silent reset
    /// on a future rename.
    enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let showIdlePill = "settings.showIdlePill"
        static let islandTintColor = "settings.islandTintColor"
        static let widgetOrder = "settings.widgetOrder"
        static let widgetEnabled = "settings.widgetEnabled"
        static let mediaNowPlayingEnabled = "settings.mediaNowPlayingEnabled"
        static let mediaAutoSwitchOnPlay = "settings.mediaAutoSwitchOnPlay"
        static let clipboardMaxCount = "settings.clipboardMaxCount"
        static let clipboardExpireInterval = "settings.clipboardExpireInterval"
        static let clipboardIgnoredApps = "settings.clipboardIgnoredApps"
        static let pomodoroConfig = "settings.pomodoroConfig"
        static let launcherEntries = "settings.launcherEntries"
    }

    /// First-launch values. Kept in a dedicated namespace so product
    /// decisions ("Launch at Login defaults ON") are easy to audit.
    enum Defaults {
        static let launchAtLogin = true
        static let showIdlePill = false
        static let islandTintColor = Color(.sRGB, red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        static let mediaNowPlayingEnabled = true
        static let mediaAutoSwitchOnPlay = false
        static let clipboardMaxCount = 50
        static let clipboardExpireInterval: TimeInterval = 86400  // 24 hours
        static let clipboardIgnoredApps: [String] = []
        static let pomodoroConfig = PomodoroConfig.default
        static let launcherEntries: [AppLauncherEntry] = []
    }

    /// Hard cap on how many apps the user can pin into the launcher row.
    /// 6 × 34pt icons + 5 × 10pt gaps = 254pt, comfortably inside the
    /// 320pt usable island content width. Enforced on both encode and
    /// decode so a manually-edited `defaults` plist can't blow past it.
    static let launcherEntriesCap: Int = 6

    // MARK: - Widget order / enabled decoders

    static func decodeWidgetOrder(_ raw: [String]?) -> [WidgetID] {
        guard let raw else { return WidgetID.defaultOrder }
        let decoded = raw.compactMap { rawValue -> WidgetID? in
            let result = WidgetID(rawValue: rawValue)
            if result == nil {
                DMLog.persistence.warning("Dropped unknown widget from persisted order: \(rawValue, privacy: .public)")
            }
            return result
        }
        // Re-append any widgets added in a newer version that the user's
        // persisted order doesn't know about yet. Preserves their existing
        // preferences and avoids silently dropping new widgets.
        let missing = WidgetID.allCases.filter { !decoded.contains($0) }
        return decoded + missing
    }

    static func decodeWidgetEnabled(_ raw: [String: Bool]?) -> [WidgetID: Bool] {
        var result: [WidgetID: Bool] = [:]
        for widget in WidgetID.allCases {
            result[widget] = true
        }
        guard let raw else { return result }
        for (key, value) in raw {
            if let id = WidgetID(rawValue: key) {
                result[id] = value
            }
        }
        return result
    }

    // MARK: - Clipboard ignored apps

    static func decodeClipboardIgnoredApps(_ data: Data?) -> [String] {
        guard let data,
              let apps = try? JSONDecoder().decode([String].self, from: data) else {
            return Defaults.clipboardIgnoredApps
        }
        return apps
    }

    // MARK: - Pomodoro config

    /// Decode the persisted `PomodoroConfig` blob, falling back to the
    /// classic defaults on any parse failure.
    static func decodePomodoroConfig(_ data: Data?) -> PomodoroConfig {
        guard let data,
              let config = try? JSONDecoder().decode(PomodoroConfig.self, from: data) else {
            return Defaults.pomodoroConfig
        }
        return config
    }

    /// Encode a `PomodoroConfig` as JSON for UserDefaults storage.
    static func encodePomodoroConfig(_ config: PomodoroConfig) -> Data? {
        try? JSONEncoder().encode(config)
    }

    // MARK: - Launcher entries

    /// Decode the persisted launcher-entry list. Returns an empty list
    /// on parse failure so a corrupted blob cannot permanently brick the
    /// launcher; defensively trims to `launcherEntriesCap` in case a
    /// user hand-edited `defaults` past the limit.
    static func decodeLauncherEntries(_ data: Data?) -> [AppLauncherEntry] {
        guard let data,
              let entries = try? JSONDecoder().decode([AppLauncherEntry].self, from: data) else {
            return Defaults.launcherEntries
        }
        return Array(entries.prefix(launcherEntriesCap))
    }

    /// Encode launcher entries, trimming to the cap so mutations that
    /// temporarily exceed it (if any ever did) cannot be persisted.
    static func encodeLauncherEntries(_ entries: [AppLauncherEntry]) -> Data? {
        try? JSONEncoder().encode(Array(entries.prefix(launcherEntriesCap)))
    }

    // MARK: - Tint color hex round-trip

    /// Decode a persisted `#RRGGBB` or `#RRGGBBAA` hex string into a
    /// SwiftUI `Color`. Returns the default tint on any parse failure so
    /// a corrupted value cannot leave the UI with nothing to draw.
    static func decodeTintColor(_ hex: String?) -> Color {
        guard let hex, let color = color(fromHex: hex) else {
            return Defaults.islandTintColor
        }
        return color
    }

    /// Encode a SwiftUI `Color` as a `#RRGGBBAA` hex string in the sRGB
    /// color space. Round-tripping through NSColor guarantees the same
    /// bytes whether the value came from a hard-coded `.sRGB` init or a
    /// user-picked `ColorPicker` selection.
    static func hex(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    static func color(fromHex hex: String) -> Color? {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6 || trimmed.count == 8,
              let value = UInt32(trimmed, radix: 16) else {
            return nil
        }

        let r, g, b, a: Double
        if trimmed.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1.0
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Compare two `Color` values by round-tripping through the hex
    /// encoder. SwiftUI's `Color` is not `Equatable` across initializers
    /// (a `Color(.sRGB, 1, 1, 1)` and `.white` compare unequal) so a
    /// bytes-level comparison is the honest way.
    static func colorsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
        hex(from: lhs) == hex(from: rhs)
    }
}
