//
//  PomodoroService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import Foundation
import Observation

/// Owns the (optional) active pomodoro session. Mirrors `TimerService` in
/// shape — same 1 Hz display tick, same wall-clock `endDate` persistence,
/// same haptic + notification conventions — but the state machine is
/// richer: phases advance automatically when `autoStartNextPhase` is on,
/// and the restore path walks the cycle forward across elapsed wall-clock
/// time when the user quits mid-run.
///
/// Deliberately separate from `TimerService` so a cycle can run alongside
/// an ad-hoc timer without their respective state machines tangling, and
/// so the extra pomodoro-specific concepts (phase, round counter, auto-
/// advance) never leak into the simpler timer code.
@Observable
@MainActor
final class PomodoroService {

    /// The current session, if any. `nil` means the widget shows its
    /// idle state with a big "Start Focus" button.
    private(set) var current: PomodoroSession?

    /// Wall-clock timestamp of the most recent user-initiated session
    /// start or resume. Parallel to `TimerService.lastActivationDate` —
    /// used by `IslandRouterView` as the tiebreaker when multiple
    /// widgets have live content, so "the thing the user just pressed
    /// start on" wins the initial selection. Auto-advance between
    /// phases does *not* bump this — only explicit user intent does,
    /// so a pomodoro running in the background stays in the background
    /// once the user has moved on to a fresh timer.
    private(set) var lastActivationDate: Date?

    /// Monotonic counter bumped once per display tick. Exists purely as
    /// an observation hook for SwiftUI: `PomodoroSession` is an
    /// `Equatable` struct whose stored fields do not change between
    /// ticks (only the computed `remaining` does, reading `Date.now`),
    /// so assigning `current = session` is a no-op from `@Observable`'s
    /// point of view and never invalidates views. Reading this counter
    /// inside a view body establishes a dependency on something that
    /// *actually* moves every second, forcing the body to re-evaluate
    /// and recompute `session.remaining` fresh from the wall clock.
    /// The value itself is meaningless — only the fact that it changes
    /// matters. Mirrors `TimerService.displayTickCounter`.
    private(set) var displayTickCounter: UInt64 = 0

    /// Set by `NotchIslandController` during wiring. Invoked when a
    /// phase transition happens (completion or auto-advance) so the
    /// notch can programmatically expand and draw attention.
    var onPhaseTransition: ((PomodoroPhase) -> Void)?

    private let settings: AppSettings
    private let persistence: PomodoroPersistence
    private let notifications: NotificationService
    private var displayTick: Foundation.Timer?

    init(
        settings: AppSettings,
        persistence: PomodoroPersistence = PomodoroPersistence(),
        notifications: NotificationService = NotificationService()
    ) {
        self.settings = settings
        self.persistence = persistence
        self.notifications = notifications
    }

    // MARK: - Lifecycle

    /// Call from `AppDelegate.applicationDidFinishLaunching`. Loads any
    /// persisted session and walks it forward against wall-clock time.
    func restore() {
        guard var persisted = persistence.load() else { return }

        // Not currently running — either paused or already finished.
        // Paused survives as-is; finished just sits waiting for dismiss.
        guard case .running = persisted.state else {
            current = persisted
            return
        }

        // Still in the current phase's window: resume the tick as normal.
        if !persisted.hasElapsed {
            current = persisted
            startDisplayTick()
            return
        }

        // Elapsed while the app was closed. Either land on `.finished`
        // and wait for the user, or walk forward through as many phases
        // as the elapsed wall-clock time covers.
        if !persisted.config.autoStartNextPhase {
            persisted.state = .finished
            current = persisted
            persistence.save(persisted)
            onPhaseTransition?(persisted.phase)
            return
        }

        walkCycleForward(from: &persisted)
        current = persisted
        persistence.save(persisted)
        // Resume the display tick if we landed inside an unfinished phase.
        if case .running = persisted.state {
            startDisplayTick()
        }
        onPhaseTransition?(persisted.phase)
    }

    /// Call from `AppDelegate.applicationWillTerminate`. Persists the
    /// current session so the next launch can resume or reconcile it.
    func persistForTermination() {
        persistence.save(current)
    }

    // MARK: - User-driven transitions

    /// Start a fresh cycle from a focus phase using the current
    /// `AppSettings.pomodoroConfig` as the session snapshot.
    func startFocus() {
        let config = settings.pomodoroConfig
        let duration = config.focusDuration
        let endDate = Date.now.addingTimeInterval(duration)
        let session = PomodoroSession(
            phase: .focus,
            completedFocusRounds: 0,
            state: .running(endDate: endDate),
            config: config
        )
        current = session
        lastActivationDate = Date.now
        persistence.save(session)

        scheduleNotification(for: .focus, seconds: duration)
        startDisplayTick()
        playStartHaptic()
    }

    func pause() {
        guard var session = current, case .running = session.state else { return }
        let remaining = session.remaining
        session.state = .paused(remaining: remaining)
        current = session
        persistence.save(session)
        notifications.cancelPomodoroPhaseCompletion()
        stopDisplayTick()
    }

    func resume() {
        guard var session = current, case .paused(let remaining) = session.state else { return }
        let endDate = Date.now.addingTimeInterval(remaining)
        session.state = .running(endDate: endDate)
        current = session
        lastActivationDate = Date.now
        persistence.save(session)
        scheduleNotification(for: session.phase, seconds: remaining)
        startDisplayTick()
    }

    /// Jump directly to the next phase without waiting for the current
    /// one to tick down. Honors the same phase-progression rules as
    /// auto-advance.
    func skipPhase() {
        guard var session = current else { return }
        advance(&session)
        current = session
        persistence.save(session)
        if case .running = session.state {
            startDisplayTick()
        } else {
            stopDisplayTick()
        }
        onPhaseTransition?(session.phase)
    }

    /// Cancel the entire cycle. Clears the session and all notifications.
    func reset() {
        notifications.cancelPomodoroPhaseCompletion()
        stopDisplayTick()
        current = nil
        persistence.save(nil)
    }

    /// User-facing dismiss for the finished state.
    func dismissFinished() {
        guard let session = current, case .finished = session.state else { return }
        current = nil
        persistence.save(nil)
    }

    // MARK: - Display tick

    private func startDisplayTick() {
        stopDisplayTick()
        let tick = Foundation.Timer(
            timeInterval: Constants.Timers.displayTickInterval,
            target: self,
            selector: #selector(onDisplayTick),
            userInfo: nil,
            repeats: true
        )
        tick.tolerance = Constants.Timers.displayTickTolerance
        RunLoop.main.add(tick, forMode: .common)
        displayTick = tick
    }

    private func stopDisplayTick() {
        displayTick?.invalidate()
        displayTick = nil
    }

    @objc
    private func onDisplayTick() {
        guard var session = current, case .running = session.state else {
            stopDisplayTick()
            return
        }

        // Bump the counter so any view that reads it in its body
        // re-evaluates against the fresh `Date.now` on the next runloop
        // cycle. Reassigning `current = session` here would be a no-op
        // because `PomodoroSession` is `Equatable` and none of its
        // stored fields have actually changed between ticks — only
        // `remaining`, which is computed.
        displayTickCounter &+= 1

        if session.hasElapsed {
            handlePhaseCompletion(&session)
        }
    }

    // MARK: - Phase transitions

    private func handlePhaseCompletion(_ session: inout PomodoroSession) {
        playFinishHaptic()
        let completedPhase = session.phase

        if session.config.autoStartNextPhase {
            advance(&session)
            current = session
            persistence.save(session)
            if case .running = session.state {
                // Keep ticking into the new phase.
                scheduleNotification(
                    for: session.phase,
                    seconds: session.config.duration(for: session.phase)
                )
            } else {
                stopDisplayTick()
            }
        } else {
            session.state = .finished
            current = session
            persistence.save(session)
            stopDisplayTick()
            notifications.cancelPomodoroPhaseCompletion()
        }

        onPhaseTransition?(completedPhase)
    }

    /// Mutate the session so it moves to the next phase. Used by both
    /// automatic phase completion and the explicit `skipPhase()` action.
    private func advance(_ session: inout PomodoroSession) {
        let next = session.nextPhase()
        var completedFocus = session.completedFocusRounds
        if session.phase == .focus {
            completedFocus += 1
        }
        let duration = session.config.duration(for: next)
        session.phase = next
        session.completedFocusRounds = completedFocus
        session.state = .running(endDate: Date.now.addingTimeInterval(duration))
    }

    /// Walk the cycle forward by repeatedly advancing until the
    /// persisted elapsed time is exhausted. Used by `restore()` after an
    /// auto-advance-on cycle spans a quit window.
    ///
    /// Caps iterations so a pathological persisted `endDate` from the
    /// distant past cannot spin here forever.
    private func walkCycleForward(from session: inout PomodoroSession) {
        let maxIterations = 100
        var guardCounter = 0

        while session.hasElapsed && guardCounter < maxIterations {
            guardCounter += 1
            advance(&session)
        }

        // Safety net: if the walk still could not land in an unfinished
        // phase (iteration cap hit, pathological 0-second durations, or
        // the single-advance limitation where `advance()` anchors
        // `endDate` to `Date.now`), land on `.finished` rather than
        // `.running` with a stale or already-elapsed `endDate`.
        if session.hasElapsed {
            session.state = .finished
        }
    }

    // MARK: - Notification helper

    private func scheduleNotification(for phase: PomodoroPhase, seconds: TimeInterval) {
        // Schedule synchronously before the display tick starts so a
        // very short phase cannot complete before the notification is
        // queued. The async Task only checks authorization; if denied,
        // it cancels the already-queued notification.
        notifications.schedulePomodoroPhaseCompletion(
            phase: phase,
            afterSeconds: seconds
        )
        Task { [notifications] in
            let granted = await notifications.requestAuthorizationIfNeeded()
            if !granted { notifications.cancelPomodoroPhaseCompletion() }
        }
    }

    // MARK: - Haptics

    private func playStartHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    private func playFinishHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
}
