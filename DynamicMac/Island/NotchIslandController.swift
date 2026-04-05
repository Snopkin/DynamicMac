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
@MainActor
final class NotchIslandController {

    let timerService: TimerService

    private var notch: DynamicNotch<IslandRouterView, EmptyView, EmptyView>?
    private var hoverDetector: NotchHoverDetector?
    private var cursorInsideNotch = false
    private var programmaticLingerTask: Task<Void, Never>?

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

        if let notch {
            Task { @MainActor in
                await notch.hide()
            }
        }
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

        guard let notch else { return }
        Task { @MainActor in
            await notch.expand()
        }
    }

    private func handleExit() {
        cursorInsideNotch = false

        // Don't collapse while a programmatic linger is in flight — that
        // task owns the collapse timing.
        guard programmaticLingerTask == nil, let notch else { return }
        Task { @MainActor in
            await notch.hide()
        }
    }

    // MARK: - Programmatic attention

    private func handleTimerFinished() {
        guard let notch else { return }
        programmaticLingerTask?.cancel()

        programmaticLingerTask = Task { @MainActor [weak self] in
            await notch.expand()
            try? await Task.sleep(for: .seconds(Constants.Timers.finishedExpandedLinger))

            guard let self else { return }
            self.programmaticLingerTask = nil

            // Only collapse if the user isn't currently hovering; if they
            // are, honor the hover state and leave the island open until
            // they move away.
            if !self.cursorInsideNotch {
                await notch.hide()
            }
        }
    }
}
