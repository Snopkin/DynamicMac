//
//  AIQAEntry.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation

/// A single question-and-answer exchange stored in the Quick Ask history.
struct AIQAEntry: Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    let timestamp: Date
}
