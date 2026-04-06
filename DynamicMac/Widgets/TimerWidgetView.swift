//
//  TimerWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Expanded-island UI for the timer widget. Three sub-states:
///   1. Idle — no active timer; show preset duration pills.
///   2. Running / paused — countdown, progress ring, pause/resume/cancel.
///   3. Finished — "Timer complete" + dismiss.
struct TimerWidgetView: View {

    @Bindable var service: TimerService

    /// Resolved transition animation passed in from `IslandRouterView`,
    /// already folding Reduce Motion + Low Power Mode into the decision.
    let animation: SwiftUI.Animation

    var body: some View {
        // Touch the tick counter so SwiftUI's @Observable tracking
        // registers a dependency on it and re-runs this body every
        // second while a timer is running. Without this read, the body
        // only observes `service.current`, which is an `Equatable`
        // struct whose stored fields never change while the countdown
        // runs (only the computed `remaining` does) — so the tick
        // assignment inside the service is a no-op from SwiftUI's
        // perspective and the label freezes at the moment the island
        // opened. The value of the counter itself is unused.
        _ = service.displayTickCounter

        return Group {
            if let timer = service.current {
                switch timer.state {
                case .finished:
                    finishedView(timer: timer)
                case .running, .paused:
                    activeView(timer: timer)
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
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            ForEach(Constants.Timers.presetMinutes, id: \.self) { minutes in
                Button {
                    service.start(
                        duration: TimeInterval(minutes * 60),
                        label: "\(minutes) min"
                    )
                } label: {
                    Text("\(minutes)m")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule().fill(.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(minutes) minute timer")
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer presets")
    }

    // MARK: - Running / paused

    private func activeView(timer: TimerModel) -> some View {
        HStack(spacing: 14) {
            ProgressRing(fraction: timer.progressFraction)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTimeRemaining(timer.remaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(timer.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(timer.label), \(formatTimeRemaining(timer.remaining)) remaining")

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                pauseOrResumeButton(timer: timer)
                iconButton(systemName: "xmark", accessibilityLabel: "Cancel timer") {
                    service.cancel()
                }
            }
        }
    }

    @ViewBuilder
    private func pauseOrResumeButton(timer: TimerModel) -> some View {
        switch timer.state {
        case .running:
            iconButton(systemName: "pause.fill", accessibilityLabel: "Pause timer") {
                service.pause()
            }
        case .paused:
            iconButton(systemName: "play.fill", accessibilityLabel: "Resume timer") {
                service.resume()
            }
        case .finished:
            EmptyView()
        }
    }

    // MARK: - Finished

    private func finishedView(timer: TimerModel) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Timer complete")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(timer.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Timer complete: \(timer.label)")

            Spacer(minLength: 0)

            iconButton(systemName: "checkmark", accessibilityLabel: "Dismiss completed timer") {
                service.dismissFinished()
            }
        }
    }

    // MARK: - Reusable bits

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
                .background(Circle().fill(.white.opacity(0.12)))
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
}

// MARK: - Progress ring

/// Circular progress indicator. Traces counter-clockwise from 12 o'clock
/// to match iOS Clock app's timer ring.
private struct ProgressRing: View {

    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 4)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: Constants.Timers.displayTickInterval), value: fraction)
        }
    }
}
