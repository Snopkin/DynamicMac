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
        persistence.save(timer)

        Task {
            let granted = await notifications.requestAuthorizationIfNeeded()
            if granted {
                notifications.scheduleTimerCompletion(label: label, afterSeconds: duration)
            }
        }

        startDisplayTick()
        playStartHaptic()
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
        persistence.save(timer)

        Task {
            let granted = await notifications.requestAuthorizationIfNeeded()
            if granted {
                notifications.scheduleTimerCompletion(label: timer.label, afterSeconds: remaining)
            }
        }

        startDisplayTick()
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

        // Forces observers to re-evaluate `current.remaining`.
        current = timer

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
