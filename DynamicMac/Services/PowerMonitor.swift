//
//  PowerMonitor.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation
import Observation

/// Tracks whether macOS Low Power Mode is enabled. Low Power Mode is
/// observable via `ProcessInfo.isLowPowerModeEnabled` plus a
/// notification when the value changes. Widgets observe this service to
/// downgrade animations and skip non-essential motion when the user is
/// trying to stretch battery life.
///
/// This is a cheap always-on service: the OS posts
/// `.NSProcessInfoPowerStateDidChange` at most once per toggle, so the
/// cost of observation is effectively zero. Keeping it behind its own
/// `@Observable` object rather than reading `ProcessInfo` directly from
/// SwiftUI views gives us a single place to add future signals
/// (thermal pressure, mains power) without touching the views again.
@Observable
@MainActor
final class PowerMonitor {

    /// `true` when macOS is currently in Low Power Mode. Updated on
    /// init and whenever the system posts a power-state change.
    private(set) var isLowPowerModeActive: Bool

    private var observer: NSObjectProtocol?

    init() {
        self.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        self.observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `.main` delivery queue guarantees main-thread execution,
            // but the closure itself is nonisolated so we hop to the
            // MainActor explicitly for the mutation.
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// Explicit teardown hook invoked from `AppDelegate.applicationWillTerminate`.
    /// Swift 6 strict concurrency does not let a nonisolated `deinit` touch
    /// MainActor-isolated state, so removal is exposed as an ordinary
    /// method instead of tucked inside `deinit`.
    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func refresh() {
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
