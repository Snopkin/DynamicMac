//
//  ClipboardPersistence.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import os

/// Persists clipboard history and pinned items as JSON in the app's
/// Application Support directory. Same file-based approach as
/// `TimerPersistence` / `PomodoroPersistence`, but uses a file instead of
/// `UserDefaults` because clipboard history can grow to hundreds of
/// entries with image data — too large for `defaults`.
struct ClipboardPersistence {

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Storage model — a flat wrapper so the JSON root is always an object.
    private struct Storage: Codable {
        var history: [ClipboardEntry]
        var pinned: [ClipboardEntry]
    }

    // MARK: - File path

    private var storageURL: URL? {
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let dir = appSupport.appendingPathComponent("DynamicMac", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("clipboard.json")
    }

    // MARK: - Load / Save

    func load() -> (history: [ClipboardEntry], pinned: [ClipboardEntry]) {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else {
            return ([], [])
        }
        do {
            let storage = try decoder.decode(Storage.self, from: data)
            return (storage.history, storage.pinned)
        } catch {
            DMLog.persistence.error("Clipboard decode failed: \(error.localizedDescription, privacy: .public)")
            return ([], [])
        }
    }

    func save(history: [ClipboardEntry], pinned: [ClipboardEntry]) {
        guard let url = storageURL else { return }
        let storage = Storage(history: history, pinned: pinned)
        do {
            let data = try encoder.encode(storage)
            try data.write(to: url, options: .atomic)
        } catch {
            DMLog.persistence.error("Clipboard encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        guard let url = storageURL else { return }
        try? fileManager.removeItem(at: url)
    }
}
