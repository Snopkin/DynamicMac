//
//  NotificationService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation
import UserNotifications

/// Thin wrapper over `UNUserNotificationCenter` for timer-completion
/// notifications. The system fires the notification even if DynamicMac
/// is suspended or the user has closed the lid, because we schedule it
/// with a `UNTimeIntervalNotificationTrigger` up front rather than
/// trying to fire it ourselves at the completion moment.
@MainActor
final class NotificationService {

    private let center = UNUserNotificationCenter.current()

    private enum RequestIdentifier {
        static let timerCompletion = "com.lidor.DynamicMac.timer.completion"
        static let pomodoroCompletion = "com.lidor.DynamicMac.pomodoro.completion"
    }

    /// Request notification authorization if we have not asked before.
    /// Safe to call multiple times — the system only prompts on the
    /// first `.notDetermined` call.
    ///
    /// - Returns: whether we are now authorized to post alerts.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted
        @unknown default:
            return false
        }
    }

    /// Schedule a local notification to fire `afterSeconds` from now.
    /// Replaces any existing pending timer notification.
    func scheduleTimerCompletion(label: String, afterSeconds seconds: TimeInterval) {
        cancelTimerCompletion()

        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = label.isEmpty ? "Your timer is up." : label
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: RequestIdentifier.timerCompletion,
            content: content,
            trigger: trigger
        )

        center.add(request) { _ in
            // Errors are non-fatal: if scheduling fails, the in-app
            // auto-expand on completion still fires from TimerService.
        }
    }

    /// Cancel the scheduled timer-completion notification (if any).
    func cancelTimerCompletion() {
        center.removePendingNotificationRequests(
            withIdentifiers: [RequestIdentifier.timerCompletion]
        )
    }

    // MARK: - Pomodoro

    /// Schedule a local notification to fire when the current pomodoro
    /// phase completes. Only the current phase is scheduled — subsequent
    /// phases in an auto-advancing cycle are notified on-the-fly by
    /// `PomodoroService` while the app is running. See the Pomodoro
    /// Settings tab footer for the quit-while-running caveat.
    ///
    /// - Parameters:
    ///   - phase: the phase that just ended (used to craft the body text
    ///     that names the *upcoming* phase to transition into).
    ///   - seconds: wall-clock seconds from now until the phase completes.
    func schedulePomodoroPhaseCompletion(
        phase: PomodoroPhase,
        afterSeconds seconds: TimeInterval
    ) {
        cancelPomodoroPhaseCompletion()

        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Pomodoro"
        content.body = body(forCompletionOf: phase)
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: RequestIdentifier.pomodoroCompletion,
            content: content,
            trigger: trigger
        )

        center.add(request) { _ in
            // Non-fatal: the in-app auto-expand on phase transition still
            // fires from PomodoroService.
        }
    }

    /// Cancel the scheduled pomodoro phase-completion notification.
    func cancelPomodoroPhaseCompletion() {
        center.removePendingNotificationRequests(
            withIdentifiers: [RequestIdentifier.pomodoroCompletion]
        )
    }

    /// Human-readable body text announcing the transition out of the
    /// given phase. The notification fires exactly at the moment the
    /// phase completes, so the wording points at what's next.
    private func body(forCompletionOf phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: return "Focus block done. Time for a break."
        case .shortBreak: return "Break over. Back to focus."
        case .longBreak: return "Long break done. Back to focus."
        }
    }
}
