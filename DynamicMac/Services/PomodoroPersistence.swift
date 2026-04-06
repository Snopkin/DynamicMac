//
//  PomodoroPersistence.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import os

/// Stores the currently active `PomodoroSession` (if any) in
/// `UserDefaults` as JSON. Mirrors `TimerPersistence` exactly — one
/// optional live session, no migration overhead, wall-clock reconciled on
/// next launch.
///
/// Kept in its own file so `PomodoroService` reads like `TimerService`
/// and future pomodoro-specific persistence tweaks (e.g. cycle history)
/// can live here without bleeding into the timer file.
struct PomodoroPersistence {

    private enum Key {
        static let currentSession = "com.lidor.DynamicMac.currentPomodoroSession"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func load() -> PomodoroSession? {
        guard let data = defaults.data(forKey: Key.currentSession) else {
            return nil
        }
        do {
            return try decoder.decode(PomodoroSession.self, from: data)
        } catch {
            DMLog.persistence.error("PomodoroSession decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ session: PomodoroSession?) {
        guard let session else {
            defaults.removeObject(forKey: Key.currentSession)
            return
        }
        do {
            let data = try encoder.encode(session)
            defaults.set(data, forKey: Key.currentSession)
        } catch {
            DMLog.persistence.error("PomodoroSession encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
