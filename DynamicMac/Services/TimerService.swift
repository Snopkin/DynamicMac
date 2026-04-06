//
//  TimerService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import Foundation
import Observation

/// Owns the (optional) active timer. A single 1-Hz display tick drives
/// the visible countdown; completion transitions happen either from the
/// tick itself (app foregrounded) or from wall-clock reconciliation on
/// relaunch (app was quit mid-run).
///
/// State flows one direction: `TimerWidgetView` mutates the service via
/// `start(duration:label:)`, `pause()`, `resume()`, `cancel()`, and the
/// service is the single source of truth the view observes.
@Observable
@MainActor
final class TimerService {

    /// The current timer, if any. `nil` means the widget is idle and
    /// should offer preset durations.
    private(set) var current: TimerModel?

    /// Wall-clock timestamp of the most recent user-initiated session
    /// start. Used by `IslandRouterView` as a tiebreaker: when two
    /// widgets both have live content (e.g. a long pomodoro still
    /// running in round 4 of 4 while the user also just started an
    /// ad-hoc timer), the one the user activated most recently wins
    /// the initial selection on the next island open. Never cleared —
    /// cancelling a timer leaves the stale timestamp alone so a later
    /// cancel-only interaction does not accidentally demote the
    /// pomodoro below the no-longer-active timer.
    private(set) var lastActivationDate: Date?

    /// Monotonic counter bumped once per display tick. Exists purely as
    /// an observation hook for SwiftUI: `TimerModel` is a `Equatable`
    /// struct whose stored fields do not change between ticks (only the
    /// computed `remaining` does, reading `Date.now`), so assigning
    /// `current = timer` is a no-op from `@Observable`'s point of view
    /// and never invalidates views. Reading this counter inside a view
    /// body establishes a dependency on something that *actually* moves
    /// every second, forcing the body to re-evaluate and recompute
    /// `timer.remaining` fresh from the wall clock. The value itself is
    /// meaningless — only the fact that it changes matters.
    private(set) var displayTickCounter: UInt64 = 0

    /// Set by `NotchIslandController` during wiring. Invoked when a
    /// running timer transitions to `.finished` so the notch can
    /// programmatically expand and draw attention.
    var onTimerFinished: (() -> Void)?

    private let persistence: TimerPersistence
    private let notifications: NotificationService
    private var displayTick: Foundation.Timer?

    init(
        persistence: TimerPersistence = TimerPersistence(),
        notifications: NotificationService = NotificationService()
    ) {
        self.persistence = persistence
        self.notifications = notifications
    }

    // MARK: - Lifecycle

    /// Call from `AppDelegate.applicationDidFinishLaunching`. Loads any
    /// persisted timer, reconciles it against wall-clock time, and
    /// resumes the display tick if the timer is still running.
    func restore() {
        guard let persisted = persistence.load() else { return }

        if persisted.hasElapsed, case .running = persisted.state {
            // Expired while the app was closed. The system notification
            // has already been delivered (or suppressed) by the scheduler;
            // surface the finished state in-app so the widget shows it
            // on first hover after relaunch.
            var finished = persisted
            finished.state = .finished
            current = finished
            persistence.save(finished)
            onTimerFinished?()
            return
        }

        current = persisted
        if case .running = persisted.state {
            startDisplayTick()
        }
    }

    /// Call from `AppDelegate.applicationWillTerminate`. Persists the
    /// current state so the next launch can resume it.
    func persistForTermination() {
        persistence.save(current)
    }

    // MARK: - User-driven transitions

    func start(duration: TimeInterval, label: String) {
        let endDate = Date.now.addingTimeInterval(duration)
        let timer = TimerModel(
            label: label,
            duration: duration,
            state: .running(endDate: endDate)
        )
        current = timer
        lastActivationDate = Date.now
        persistence.save(timer)

        // Schedule before starting the tick so a very short timer
        // cannot complete before the notification is queued.
        notifications.scheduleTimerCompletion(label: label, afterSeconds: duration)
        startDisplayTick()
        playStartHaptic()

        Task { [notifications] in
            let granted = await notifications.requestAuthorizationIfNeeded()
            if !granted { notifications.cancelTimerCompletion() }
        }
    }

    func pause() {
        guard var timer = current, case .running = timer.state else { return }
        let remaining = timer.remaining
        timer.state = .paused(remaining: remaining)
        current = timer
        persistence.save(timer)
        notifications.cancelTimerCompletion()
        stopDisplayTick()
    }

    func resume() {
        guard var timer = current, case .paused(let remaining) = timer.state else { return }
        let endDate = Date.now.addingTimeInterval(remaining)
        timer.state = .running(endDate: endDate)
        current = timer
        lastActivationDate = Date.now
        persistence.save(timer)

        notifications.scheduleTimerCompletion(label: timer.label, afterSeconds: remaining)
        startDisplayTick()

        Task { [notifications] in
            let granted = await notifications.requestAuthorizationIfNeeded()
            if !granted { notifications.cancelTimerCompletion() }
        }
    }

    func cancel() {
        notifications.cancelTimerCompletion()
        stopDisplayTick()
        current = nil
        persistence.save(nil)
    }

    /// User-facing dismiss for the finished state. Clears the timer.
    func dismissFinished() {
        guard let timer = current, case .finished = timer.state else { return }
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
        guard var timer = current, case .running = timer.state else {
            stopDisplayTick()
            return
        }

        // Bump the counter so any view that reads it in its body
        // re-evaluates against the fresh `Date.now` on the next runloop
        // cycle. Reassigning `current = timer` here would be a no-op
        // because `TimerModel` is `Equatable` and nothing stored on the
        // struct has actually changed — only `remaining`, which is
        // computed.
        displayTickCounter &+= 1

        if timer.hasElapsed {
            timer.state = .finished
            current = timer
            persistence.save(timer)
            stopDisplayTick()
            playFinishHaptic()
            onTimerFinished?()
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
