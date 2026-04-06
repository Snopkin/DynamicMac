//
//  ResponseTextParser.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation

/// A segment of parsed response text — either plain markdown or a code
/// span that should be rendered with a copy button.
enum ResponseSegment: Identifiable {
    case text(String)
    case code(String)

    var id: String {
        switch self {
        case .text(let s): return "t:\(s.prefix(40))\(s.hashValue)"
        case .code(let s): return "c:\(s)"
        }
    }
}

/// Splits a markdown response string into alternating `.text` and `.code`
/// segments by extracting single-backtick code spans. Multi-line fenced
/// code blocks (```) are left inside `.text` segments — they're rare in
/// 1-3 sentence answers and SwiftUI's `AttributedString(markdown:)` already
/// renders them fine.
enum ResponseTextParser {

    static func parse(_ input: String) -> [ResponseSegment] {
        var segments: [ResponseSegment] = []
        var remaining = input[...]

        while !remaining.isEmpty {
            // Find the next single backtick that isn't part of a ``` fence.
            guard let openRange = remaining.range(of: "`"),
                  !isFenceTick(in: remaining, at: openRange) else {
                // No more code spans — rest is plain text.
                segments.append(.text(String(remaining)))
                break
            }

            // Capture the text before the opening backtick.
            let textBefore = remaining[remaining.startIndex..<openRange.lowerBound]
            if !textBefore.isEmpty {
                segments.append(.text(String(textBefore)))
            }

            // Look for the closing backtick.
            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "`"),
               !isFenceTick(in: afterOpen, at: closeRange) {
                let codeContent = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                if !codeContent.isEmpty, !codeContent.allSatisfy({ $0.isWhitespace }) {
                    segments.append(.code(codeContent))
                } else {
                    // Empty backticks — emit as text.
                    segments.append(.text("`\(codeContent)`"))
                }
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                // No closing backtick — treat the rest as text.
                segments.append(.text(String(remaining[openRange.lowerBound...])))
                break
            }
        }

        return segments
    }

    /// Returns `true` if the backtick at `range` is part of a triple-backtick
    /// fence (``` or more). We don't want to split on fenced code blocks.
    private static func isFenceTick(in str: Substring, at range: Range<Substring.Index>) -> Bool {
        // Check if the next character after this backtick is also a backtick.
        let afterEnd = range.upperBound
        if afterEnd < str.endIndex, str[afterEnd] == "`" {
            return true
        }
        // Check if the character before this backtick is also a backtick.
        if range.lowerBound > str.startIndex {
            let before = str.index(before: range.lowerBound)
            if str[before] == "`" {
                return true
            }
        }
        return false
    }
}
