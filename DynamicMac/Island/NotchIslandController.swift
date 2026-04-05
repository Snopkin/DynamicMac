//
//  NotchIslandController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import DynamicNotchKit
import SwiftUI

/// Owns the `DynamicNotch` overlay plus a `NotchHoverDetector` that triggers
/// expand/hide as the cursor enters and leaves the notch region, and a
/// reference to the `TimerService` so the expanded content can route to
/// the timer widget or a placeholder.
///
/// DynamicNotchKit's `init` only registers the notch; it does not create any
/// NSPanel or listen for hovers until `expand()` is called. The hover
/// detector bridges that gap with an always-on thin NSPanel + NSTrackingArea.
/// `hoverBehavior: .keepVisible` on the notch keeps the island open while
/// the cursor is inside the expanded content, so a brief cursor exit from
/// the notch strip into the expanded island area does not dismiss the view.
///
/// When a timer completes, `TimerService.onTimerFinished` fires and we
/// programmatically `expand()` the notch for `finishedExpandedLinger`
/// seconds to draw the user's attention, then collapse.
///
/// ## Notch task serialization
///
/// All calls into `DynamicNotch.expand()` / `DynamicNotch.hide()` are
/// threaded through a single serial chain via `enqueueNotchTask`. This
/// works around a continuation-leak bug in DynamicNotchKit 1.0.0 where
/// calling `expand()` while a previous `hide()` is still animating
/// cancels the hide's internal `closePanelTask`, stranding the
/// `withCheckedContinuation` that `public func hide()` awaits and
/// triggering a "SWIFT TASK CONTINUATION MISUSE: hide() leaked its
/// continuation" runtime warning. By guaranteeing that `expand()` only
/// runs after any in-flight `hide()` has fully completed, the cancel
/// path inside DynamicNotchKit becomes unreachable.
@MainActor
final class NotchIslandController {

    let timerService: TimerService

    private var notch: DynamicNotch<IslandRouterView, EmptyView, EmptyView>?
    private var hoverDetector: NotchHoverDetector?
    private var cursorInsideNotch = false
    private var programmaticLingerTask: Task<Void, Never>?

    /// Tail of the serialized expand/hide task chain. Each new request
    /// awaits this task before running its operation and then becomes
    /// the new tail.
    private var pendingNotchTask: Task<Void, Never>?

    init(timerService: TimerService) {
        self.timerService = timerService
    }

    func start() {
        // Strongly capture `timerService` so the SwiftUI view has a stable
        // reference even if the controller is later torn down.
        let service = timerService
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto
        ) {
            IslandRouterView(timerService: service)
        }
        self.notch = notch

        let detector = NotchHoverDetector(
            onEnter: { [weak self] in
                self?.handleEnter()
            },
            onExit: { [weak self] in
                self?.handleExit()
            }
        )
        detector.start()
        self.hoverDetector = detector

        timerService.onTimerFinished = { [weak self] in
            self?.handleTimerFinished()
        }
    }

    func shutdown() {
        programmaticLingerTask?.cancel()
        programmaticLingerTask = nil

        timerService.onTimerFinished = nil

        hoverDetector?.stop()
        hoverDetector = nil

        // Enqueue the final hide on the serial chain so it runs after any
        // in-flight expand, then drop the notch reference. Do not cancel
        // pendingNotchTask — cancellation is the exact code path that
        // leaks DynamicNotchKit's hide continuation.
        requestHide()
        pendingNotchTask = nil
        notch = nil
    }

    // MARK: - Hover handlers

    private func handleEnter() {
        cursorInsideNotch = true
        // A cursor-driven expansion cancels any pending programmatic
        // collapse, so the user can interact with a finished-state widget
        // without it disappearing underneath them.
        programmaticLingerTask?.cancel()
        programmaticLingerTask = nil

        requestExpand()
    }

    private func handleExit() {
        cursorInsideNotch = false

        // Don't collapse while a programmatic linger is in flight — that
        // task owns the collapse timing.
        guard programmaticLingerTask == nil else { return }
        requestHide()
    }

    // MARK: - Programmatic attention

    private func handleTimerFinished() {
        programmaticLingerTask?.cancel()

        programmaticLingerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.requestExpand()

            try? await Task.sleep(for: .seconds(Constants.Timers.finishedExpandedLinger))

            self.programmaticLingerTask = nil

            // Only collapse if the user isn't currently hovering; if they
            // are, honor the hover state and leave the island open until
            // they move away.
            if !self.cursorInsideNotch {
                self.requestHide()
            }
        }
    }

    // MARK: - Serialized notch operations

    /// Appends a `notch.expand()` call to the serial chain. Returns
    /// immediately; the expand happens after any previously-queued hide.
    private func requestExpand() {
        enqueueNotchOperation { notch in
            await notch.expand()
        }
    }

    /// Appends a `notch.hide()` call to the serial chain.
    private func requestHide() {
        enqueueNotchOperation { notch in
            await notch.hide()
        }
    }

    /// Core enqueue primitive. Chains the new operation after the current
    /// tail, captures the notch strongly for the duration of the call so
    /// shutdown's `self.notch = nil` doesn't race the operation, and
    /// installs the new task as the chain tail.
    private func enqueueNotchOperation(
        _ operation: @escaping @MainActor (DynamicNotch<IslandRouterView, EmptyView, EmptyView>) async -> Void
    ) {
        guard let notch else { return }
        let previous = pendingNotchTask

        pendingNotchTask = Task { @MainActor in
            _ = await previous?.value
            await operation(notch)
        }
    }
}
