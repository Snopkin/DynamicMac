//
//  PomodoroWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Expanded-island UI for the pomodoro widget. Three sub-states mirror
/// `TimerWidgetView`:
///   1. Idle — no active session; big "Start Focus" button + round dots.
///   2. Active — running or paused; phase-tinted progress ring + MM:SS.
///   3. Finished — phase-appropriate message + reset button.
///
/// Deliberately duplicates the ~18-line `ProgressRing` helper from the
/// timer widget rather than coupling the two widgets through a shared
/// file. 18 lines is cheap; cross-widget coupling is expensive when one
/// widget's visual language drifts from the other.
struct PomodoroWidgetView: View {

    @Bindable var service: PomodoroService
    @Bindable var settings: AppSettings

    /// Resolved transition animation passed in from `IslandRouterView`.
    let animation: SwiftUI.Animation

    var body: some View {
        // Touch the tick counter so SwiftUI's @Observable tracking
        // registers a dependency on it and re-runs this body every
        // second while a session is running. See the matching comment
        // in `TimerWidgetView` — same struct-equality problem applies
        // here, since `PomodoroSession.remaining` is computed from
        // `Date.now` and the stored fields do not change between ticks.
        _ = service.displayTickCounter

        return Group {
            if let session = service.current {
                switch session.state {
                case .finished:
                    finishedView(session: session)
                case .running, .paused:
                    activeView(session: session)
                }
            } else {
                idleView
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(animation, value: service.current)
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pomodoro")
                    .font(.headline)
                    .foregroundStyle(.white)
                roundDots(completed: 0)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pomodoro idle")

            Spacer(minLength: 0)

            Button {
                service.startFocus()
            } label: {
                Text("Start Focus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start focus block")
        }
    }

    // MARK: - Active

    private func activeView(session: PomodoroSession) -> some View {
        HStack(spacing: 14) {
            ProgressRing(
                fraction: session.progressFraction,
                tint: tint(for: session.phase)
            )
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTimeRemaining(session.remaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(subtitle(for: session))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                roundDots(completed: session.completedFocusRounds)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(session.phase.displayName), \(formatTimeRemaining(session.remaining)) remaining, round \(session.completedFocusRounds + 1)")

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                pauseOrResumeButton(session: session)
                iconButton(systemName: "forward.fill", accessibilityLabel: "Skip to next phase") {
                    service.skipPhase()
                }
                iconButton(systemName: "xmark", accessibilityLabel: "Cancel pomodoro") {
                    service.reset()
                }
            }
        }
    }

    @ViewBuilder
    private func pauseOrResumeButton(session: PomodoroSession) -> some View {
        switch session.state {
        case .running:
            iconButton(systemName: "pause.fill", accessibilityLabel: "Pause pomodoro") {
                service.pause()
            }
        case .paused:
            iconButton(systemName: "play.fill", accessibilityLabel: "Resume pomodoro") {
                service.resume()
            }
        case .finished:
            EmptyView()
        }
    }

    // MARK: - Finished

    private func finishedView(session: PomodoroSession) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(tint(for: session.phase))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.phase.displayName) done")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(finishedSubtitle(for: session))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pomodoro phase complete: \(session.phase.displayName)")

            Spacer(minLength: 0)

            iconButton(systemName: "checkmark", accessibilityLabel: "Dismiss completed pomodoro") {
                service.dismissFinished()
            }
        }
    }

    // MARK: - Subview helpers

    private func roundDots(completed: Int) -> some View {
        let rounds = max(1, settings.pomodoroConfig.roundsBeforeLongBreak)
        return HStack(spacing: 4) {
            ForEach(0..<rounds, id: \.self) { index in
                Circle()
                    .fill(index < completed ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func subtitle(for session: PomodoroSession) -> String {
        let total = max(1, session.config.roundsBeforeLongBreak)
        let current = min(session.completedFocusRounds + 1, total)
        return "\(session.phase.displayName) • Round \(current) of \(total)"
    }

    private func finishedSubtitle(for session: PomodoroSession) -> String {
        switch session.phase {
        case .focus: return "Time for a break."
        case .shortBreak, .longBreak: return "Back to focus when ready."
        }
    }

    private func tint(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus: return .green
        case .shortBreak: return .cyan
        case .longBreak: return .purple
        }
    }
}

// MARK: - Progress ring

/// Circular progress indicator. Duplicated from `TimerWidgetView`
/// intentionally — the two widgets should be free to visually diverge
/// without a shared helper file dragging them back together.
private struct ProgressRing: View {

    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 4)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: Constants.Timers.displayTickInterval), value: fraction)
        }
    }
}
