//
//  ClipboardService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import Foundation
import Observation
import os

/// Monitors `NSPasteboard.general` for changes and maintains a rolling
/// clipboard history. Pinned items persist across relaunches; unpinned
/// items are trimmed by count and age according to user settings.
///
/// Polling approach: `NSPasteboard` does not offer a notification-based
/// API — the canonical technique is to poll `changeCount` on a timer.
/// 500ms strikes the right balance between responsiveness and idle CPU.
@Observable
@MainActor
final class ClipboardService {

    // MARK: - Published state

    /// Most-recent-first history of captured clips (excluding pinned).
    private(set) var history: [ClipboardEntry] = []

    /// User-pinned clips that survive across relaunches and are not
    /// subject to the max-count or expiry trim.
    private(set) var pinned: [ClipboardEntry] = []

    // MARK: - Dependencies

    private let settings: AppSettings
    private let persistence = ClipboardPersistence()

    // MARK: - Internal state

    private var pollTimer: Foundation.Timer?
    private var lastChangeCount: Int = 0

    /// Set when `recopy(_:)` writes to the pasteboard so the next poll
    /// doesn't re-capture the item we just placed.
    private var skipNextCapture = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        let stored = persistence.load()
        history = stored.history
        pinned = stored.pinned

        // Seed with the current changeCount so we don't immediately
        // capture whatever is on the clipboard at launch.
        lastChangeCount = NSPasteboard.general.changeCount

        let timer = Foundation.Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        persistNow()
    }

    /// Called from `AppDelegate.applicationWillTerminate` so in-flight
    /// state is not lost.
    func persistForTermination() {
        persistNow()
    }

    // MARK: - Actions

    /// Place the entry's content back on the system clipboard.
    func recopy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .url(let url):
            pasteboard.setString(url.absoluteString, forType: .string)
        case .image(let data):
            pasteboard.setData(data, forType: .png)
        }

        skipNextCapture = true
    }

    func pin(_ entry: ClipboardEntry) {
        var updated = entry
        updated.isPinned = true

        // Move from history to pinned.
        history.removeAll { $0.id == entry.id }
        if !pinned.contains(where: { $0.id == entry.id }) {
            pinned.insert(updated, at: 0)
        }
        persistNow()
    }

    func unpin(_ entry: ClipboardEntry) {
        var updated = entry
        updated.isPinned = false

        pinned.removeAll { $0.id == entry.id }
        // Re-insert at the top of history so it doesn't vanish.
        history.insert(updated, at: 0)
        trimHistory()
        persistNow()
    }

    func removeEntry(_ entry: ClipboardEntry) {
        history.removeAll { $0.id == entry.id }
        pinned.removeAll { $0.id == entry.id }
        persistNow()
    }

    func clearHistory() {
        history.removeAll()
        persistNow()
    }

    func clearAll() {
        history.removeAll()
        pinned.removeAll()
        persistence.clear()
    }

    /// Combined list for display: pinned first, then history.
    var allEntries: [ClipboardEntry] {
        pinned + history
    }

    // MARK: - Polling

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if skipNextCapture {
            skipNextCapture = false
            return
        }

        // Check if the frontmost app is in the ignored list.
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier,
           settings.clipboardIgnoredApps.contains(bundleID) {
            return
        }

        guard let content = snapshotPasteboard(pasteboard) else { return }

        // De-duplicate: if the same content was just captured, skip.
        if let latest = history.first, latest.content == content {
            return
        }
        if pinned.contains(where: { $0.content == content }) {
            return
        }

        let entry = ClipboardEntry(
            id: UUID(),
            timestamp: Date(),
            content: content,
            isPinned: false
        )
        history.insert(entry, at: 0)
        trimHistory()
        persistNow()
    }

    /// Read the richest supported type from the pasteboard.
    /// Priority: image > URL > plain text.
    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> ClipboardContent? {
        // Image (PNG or TIFF).
        if let imageData = pasteboard.data(forType: .png) {
            // Cap image data at 1 MB to avoid bloating storage.
            if imageData.count <= 1_048_576 {
                return .image(imageData)
            }
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.tiffRepresentation.flatMap({
               NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
           }),
           pngData.count <= 1_048_576 {
            return .image(pngData)
        }

        // URL (only if it looks like a real URL, not just any string).
        if let urlString = pasteboard.string(forType: .string),
           let url = URL(string: urlString),
           let scheme = url.scheme,
           ["http", "https", "ftp", "ftps"].contains(scheme.lowercased()),
           url.host != nil {
            return .url(url)
        }

        // Plain text.
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            // Cap text at 10,000 characters to avoid extreme entries.
            let trimmed = string.count > 10_000
                ? String(string.prefix(10_000))
                : string
            return .text(trimmed)
        }

        return nil
    }

    // MARK: - Trim & persist

    private func trimHistory() {
        let maxCount = settings.clipboardMaxCount

        // Trim by count.
        if history.count > maxCount {
            history = Array(history.prefix(maxCount))
        }

        // Trim by age.
        let expiry = settings.clipboardExpireInterval
        if expiry > 0 {
            let cutoff = Date().addingTimeInterval(-expiry)
            history.removeAll { $0.timestamp < cutoff }
        }
    }

    private func persistNow() {
        persistence.save(history: history, pinned: pinned)
    }
}
