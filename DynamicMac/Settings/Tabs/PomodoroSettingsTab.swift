//
//  PomodoroSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Pomodoro configuration: focus / short break / long break durations,
/// rounds before a long break, auto-advance toggle, and a reset-to-
/// classic button. Writes straight through to `AppSettings.pomodoroConfig`
/// — a running session snapshots its own copy on start so mid-run edits
/// don't corrupt the in-flight cycle.
struct PomodoroSettingsTab: View {

    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                durationStepper(
                    title: "Focus",
                    valueMinutes: binding(for: \.focusDuration),
                    range: 1...90
                )
                durationStepper(
                    title: "Short break",
                    valueMinutes: binding(for: \.shortBreakDuration),
                    range: 1...30
                )
                durationStepper(
                    title: "Long break",
                    valueMinutes: binding(for: \.longBreakDuration),
                    range: 5...60
                )
            } header: {
                Text("Durations")
            }

            Section {
                Stepper(
                    value: roundsBinding,
                    in: 2...8
                ) {
                    HStack {
                        Text("Focus rounds before long break")
                        Spacer()
                        Text("\(settings.pomodoroConfig.roundsBeforeLongBreak)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Rounds")
            }

            Section {
                Toggle("Auto-start next phase", isOn: autoStartBinding)
            } header: {
                Text("Automation")
            } footer: {
                Text("Notifications only fire for the current phase while DynamicMac is quit. Keep DynamicMac running for full-cycle reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Classic (25 / 5 / 15)") {
                    settings.pomodoroConfig = .default
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Binding helpers

    /// Build a stepper over one of the three `TimeInterval` duration
    /// fields by projecting through a writable keypath and clamping to
    /// whole-minute steps. Reassigns the entire `pomodoroConfig` struct
    /// on each edit so the `didSet` observer fires and persists the
    /// change.
    private func durationStepper(
        title: String,
        valueMinutes: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: valueMinutes, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(valueMinutes.wrappedValue) min")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func binding(for keyPath: WritableKeyPath<PomodoroConfig, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int((settings.pomodoroConfig[keyPath: keyPath] / 60).rounded()) },
            set: { newValue in
                var edited = settings.pomodoroConfig
                edited[keyPath: keyPath] = TimeInterval(newValue * 60)
                settings.pomodoroConfig = edited
            }
        )
    }

    private var roundsBinding: Binding<Int> {
        Binding(
            get: { settings.pomodoroConfig.roundsBeforeLongBreak },
            set: { newValue in
                var edited = settings.pomodoroConfig
                edited.roundsBeforeLongBreak = newValue
                settings.pomodoroConfig = edited
            }
        )
    }

    private var autoStartBinding: Binding<Bool> {
        Binding(
            get: { settings.pomodoroConfig.autoStartNextPhase },
            set: { newValue in
                var edited = settings.pomodoroConfig
                edited.autoStartNextPhase = newValue
                settings.pomodoroConfig = edited
            }
        )
    }
}
