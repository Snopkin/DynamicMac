//
//  PomodoroModel.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation

/// The three phases of a classic pomodoro cycle. Focus blocks are
/// punctuated by short breaks; after every `roundsBeforeLongBreak` focus
/// rounds, the next break is a long one. Raw values are stable so
/// persisted sessions survive app upgrades.
enum PomodoroPhase: String, Codable, Equatable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    /// Human-readable label shown in the expanded island and the
    /// finished-state message.
    var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    /// SF Symbol paired with each phase inside the idle + finished views.
    var systemImage: String {
        switch self {
        case .focus: return "leaf.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "bed.double.fill"
        }
    }
}

/// User-configurable pomodoro parameters. Lives on `AppSettings` and is
/// snapshotted into each `PomodoroSession` at start time so mid-run edits
/// cannot corrupt an in-flight session.
struct PomodoroConfig: Codable, Equatable {

    /// Length of a focus block, in seconds.
    var focusDuration: TimeInterval

    /// Length of a short break, in seconds.
    var shortBreakDuration: TimeInterval

    /// Length of a long break, in seconds.
    var longBreakDuration: TimeInterval

    /// How many focus blocks happen before a long break. After the Nth
    /// focus the next phase is `.longBreak` instead of `.shortBreak`.
    var roundsBeforeLongBreak: Int

    /// When `true`, finishing a phase immediately starts the next phase
    /// instead of landing on a `.finished` state and waiting for the user.
    var autoStartNextPhase: Bool

    /// Classic 25 / 5 / 15 / 4-rounds defaults with auto-advance on.
    static let `default` = PomodoroConfig(
        focusDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        roundsBeforeLongBreak: 4,
        autoStartNextPhase: true
    )

    /// Duration for the given phase.
    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return focusDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }
}

/// A single pomodoro session currently in flight. Persisted across
/// launches so quitting mid-focus resumes against wall-clock time.
///
/// The running state stores an absolute `endDate`, mirroring `TimerModel`,
/// so restore() can compare it to `Date.now` and either resume or walk
/// the cycle forward.
struct PomodoroSession: Codable, Equatable {

    enum State: Codable, Equatable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    let id: UUID
    var phase: PomodoroPhase
    /// Number of focus phases completed so far in the current cycle. Used
    /// to decide whether the next break is short or long, and to render
    /// the round-progress dots on the idle view.
    var completedFocusRounds: Int
    var state: State
    /// Snapshot of the config at start time. Using this instead of the
    /// live `AppSettings.pomodoroConfig` means editing durations mid-run
    /// applies on the next session start rather than mangling the current
    /// one.
    var config: PomodoroConfig

    init(
        id: UUID = UUID(),
        phase: PomodoroPhase,
        completedFocusRounds: Int,
        state: State,
        config: PomodoroConfig
    ) {
        self.id = id
        self.phase = phase
        self.completedFocusRounds = completedFocusRounds
        self.state = state
        self.config = config
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

    /// Fraction of the current phase's duration still remaining, in `0...1`.
    /// Drives the progress ring in `PomodoroWidgetView`.
    var progressFraction: Double {
        let total = config.duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    /// True when the current phase has reached zero but may not yet have
    /// been transitioned by the service.
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

    /// Compute the phase that follows this one according to the session's
    /// config. Does not mutate — `PomodoroService` assembles the next
    /// `PomodoroSession` from the returned phase.
    func nextPhase() -> PomodoroPhase {
        switch phase {
        case .focus:
            // The focus we just finished contributes one to the count for
            // the purposes of deciding the upcoming break length.
            let upcomingFocusRounds = completedFocusRounds + 1
            if upcomingFocusRounds % max(1, config.roundsBeforeLongBreak) == 0 {
                return .longBreak
            }
            return .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }
}
