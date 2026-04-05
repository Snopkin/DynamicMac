//
//  TimerModel.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// A single countdown timer. Persisted across launches so a timer that
/// spans a quit/relaunch cycle can be resumed against wall-clock time.
///
/// The running state stores an absolute `endDate` rather than a
/// `timeRemaining`, so when we decode on launch we can simply compare it
/// to `Date.now` and either resume (endDate is still in the future) or
/// surface it as finished (endDate has already passed).
struct TimerModel: Codable, Equatable {

    enum State: Codable, Equatable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    let id: UUID
    var label: String
    var duration: TimeInterval
    var state: State

    init(
        id: UUID = UUID(),
        label: String,
        duration: TimeInterval,
        state: State
    ) {
        self.id = id
        self.label = label
        self.duration = duration
        self.state = state
    }

    /// Seconds remaining against the current wall clock. Clamped to zero.
    var remaining: TimeInterval {
        switch state {
        case .running(let endDate):
            return max(0, endDate.timeIntervalSince(Date.now))
        case .paused(let remaining):
            return max(0, remaining)
        case .finished:
            return 0
        }
    }

    /// Fraction of the original duration still remaining, in `0...1`.
    /// Used to drive the progress ring in `TimerWidgetView`.
    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining / duration))
    }

    /// True when the timer has reached zero but may not yet have been
    /// transitioned to `.finished` by the service.
    var hasElapsed: Bool {
        switch state {
        case .running(let endDate):
            return endDate <= Date.now
        case .paused(let remaining):
            return remaining <= 0
        case .finished:
            return true
        }
    }
}
