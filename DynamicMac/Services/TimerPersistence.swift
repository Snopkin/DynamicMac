//
//  TimerPersistence.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// Stores the currently active `TimerModel` (if any) in `UserDefaults`
/// as JSON. One optional timer at a time — MVP scope.
///
/// We deliberately avoid SwiftData here: there is at most one live timer,
/// the schema is tiny and rarely changes, and UserDefaults round-trips
/// atomically with no migration overhead.
struct TimerPersistence {

    private enum Key {
        static let currentTimer = "com.lidor.DynamicMac.currentTimer"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func load() -> TimerModel? {
        guard let data = defaults.data(forKey: Key.currentTimer) else {
            return nil
        }
        return try? decoder.decode(TimerModel.self, from: data)
    }

    func save(_ timer: TimerModel?) {
        guard let timer else {
            defaults.removeObject(forKey: Key.currentTimer)
            return
        }
        guard let data = try? encoder.encode(timer) else {
            return
        }
        defaults.set(data, forKey: Key.currentTimer)
    }
}
