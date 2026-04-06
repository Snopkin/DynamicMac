//
//  NotchIslandController+Attention.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import os

/// Programmatic attention handlers — timer completion and pomodoro
/// phase transition — kept in their own file so
/// `NotchIslandController.swift` stays focused on hover state and the
/// lifecycle. Sibling to `NotchIslandController+Chain.swift`.
///
/// Both handlers follow the same "briefly expand, then let the hover
/// state take over" pattern: cancel any in-flight linger, open the
/// island, wait `finishedExpandedLinger` seconds, and then hide unless
/// the cursor has meanwhile entered the notch region (in which case the
/// regular hover handlers own the collapse timing).
extension NotchIslandController {

    /// Called when a `TimerService` timer transitions to `.finished`.
    /// Expands the island, lingers, and then collapses unless the user
    /// is currently hovering.
    func handleTimerFinished() {
        DMLog.island.debug("handleTimerFinished → linger")
        lingerExpanded(source: "timerFinished")
    }

    /// Called when a `PomodoroService` phase completes (either naturally
    /// or via the user's Skip action). Same shape as the timer path —
    /// the two kinds of attention are visually equivalent at the island
    /// level, so the wiring reuses one helper.
    func handlePomodoroPhaseTransition() {
        DMLog.island.debug("handlePomodoroPhaseTransition → linger")
        lingerExpanded(source: "pomodoroPhase")
    }

    /// Shared linger implementation. Cancels any prior linger task,
    /// requests an expand, sleeps for `Constants.Timers.finishedExpandedLinger`
    /// seconds, then collapses unless the cursor is inside the notch.
    ///
    /// The `source` string is threaded through to the requestExpand /
    /// requestHide log lines so diagnosing which subsystem opened the
    /// island does not require guessing at `#function` defaults.
    private func lingerExpanded(source: String) {
        programmaticLingerTask?.cancel()

        programmaticLingerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.requestExpand(caller: "linger(\(source))")

            try? await Task.sleep(for: .seconds(Constants.Timers.finishedExpandedLinger))

            self.programmaticLingerTask = nil

            // Only collapse if the user isn't currently hovering; if they
            // are, honor the hover state and leave the island open until
            // they move away.
            if !self.isCursorInsideNotch {
                self.requestHide(caller: "linger(\(source))")
            }
        }
    }
}
