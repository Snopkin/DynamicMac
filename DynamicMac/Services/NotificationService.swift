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
}
