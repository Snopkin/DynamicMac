//
//  NotchIslandController+Chain.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import DynamicNotchKit
import os
import SwiftUI

/// Serialized expand/hide chain plus the coalescing logic that lets
/// `NotchIslandController` talk to `DynamicNotch` without tripping its
/// continuation-leak bug or the hover-animation re-enter loop.
///
/// See `NotchIslandController.swift` for the full story; this file just
/// holds the implementations of `requestExpand`, `requestHide`, and
/// `enqueueNotchOperation` so the main controller file stays focused on
/// hover state and programmatic attention.
extension NotchIslandController {

    /// Appends a `notch.expand()` call to the serial chain unless the
    /// chain is already aimed at expanded, in which case the request is
    /// dropped. Returns immediately; the expand happens after any
    /// previously-queued hide.
    ///
    /// The `caller` default parameter captures `#function` at the call
    /// site so the log line identifies *who* requested the expand. This
    /// is invaluable when diagnosing spurious re-opens — a request that
    /// isn't from `handleEnter` points at a programmatic code path
    /// (timer-finished linger, pomodoro phase transition, etc.).
    func requestExpand(caller: String = #function) {
        guard intendedState != .expanded else {
            DMLog.island.debug("requestExpand coalesced from \(caller, privacy: .public) — already intending expanded")
            return
        }
        intendedState = .expanded
        DMLog.island.debug("requestExpand enqueued from \(caller, privacy: .public)")
        enqueueNotchOperation(label: "expand") { notch in
            await notch.expand()
        }
    }

    /// Hides the notch as fast as possible. If an expand is currently
    /// in-flight on the chain, cancels it — `expand()` uses
    /// `try? await Task.sleep` so cancellation is safe. We never cancel
    /// during a `hide()` because `hide()` uses `withCheckedContinuation`
    /// and cancelling would leak the continuation.
    func requestHide(caller: String = #function) {
        guard intendedState != .hidden else {
            DMLog.island.debug("requestHide coalesced from \(caller, privacy: .public) — already intending hidden")
            return
        }
        intendedState = .hidden

        // If the chain is running an expand, cancel it so the hide
        // doesn't wait for the expand's 400ms animation sleep to finish.
        // Safe because expand()'s internal sleeps use try? and handle
        // cancellation gracefully. The isRunningHide flag ensures we
        // never cancel during a hide (continuation-leak risk).
        if !isRunningHide {
            pendingNotchTask?.cancel()
            pendingNotchTask = nil
        }

        DMLog.island.debug("requestHide enqueued from \(caller, privacy: .public)")
        enqueueNotchOperation(label: "hide") { [weak self] notch in
            self?.isRunningHide = true
            await notch.hide()
            self?.isRunningHide = false
        }
    }

    /// Core enqueue primitive. Chains the new operation after the current
    /// tail, captures the notch strongly for the duration of the call so
    /// shutdown's `self.notch = nil` doesn't race the operation, and
    /// installs the new task as the chain tail. The label is used only
    /// for logging.
    func enqueueNotchOperation(
        label: String,
        _ operation: @escaping @MainActor (DynamicNotch<IslandRouterView, EmptyView, EmptyView>) async -> Void
    ) {
        guard let notch = self.notch else { return }
        let previous = pendingNotchTask

        pendingNotchTask = Task { @MainActor in
            _ = await previous?.value
            DMLog.island.debug("chain running \(label, privacy: .public)")
            await operation(notch)
            DMLog.island.debug("chain finished \(label, privacy: .public)")
        }
    }
}
