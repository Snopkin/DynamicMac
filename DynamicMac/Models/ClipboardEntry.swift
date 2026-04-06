//
//  ClipboardEntry.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation

/// A single captured clipboard snapshot. Persisted via JSON so pinned
/// items survive across app relaunches.
struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let content: ClipboardContent
    var isPinned: Bool

    /// Truncated text preview for display in the island widget row.
    /// Returns `nil` for image content (the view shows a thumbnail instead).
    var textPreview: String? {
        switch content {
        case .text(let string):
            return string
        case .url(let url):
            return url.absoluteString
        case .image:
            return nil
        }
    }
}

/// The payload captured from `NSPasteboard`. Only one variant is stored
/// per entry — we snapshot the richest type available at capture time
/// (image > URL > plain text).
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case url(URL)
    /// PNG-encoded image data. Decoded on demand for thumbnail rendering;
    /// not displayed inline in the Codable representation.
    case image(Data)
}
