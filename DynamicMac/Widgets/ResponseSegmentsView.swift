//
//  ResponseSegmentsView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Renders a list of `ResponseSegment`s as a flowing layout. Plain text
/// segments use markdown-attributed rendering; code spans are styled chips
/// with a small copy button beside them.
struct ResponseSegmentsView: View {

    let segments: [ResponseSegment]
    let isStreaming: Bool
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Split segments into lines. Each line is a group of segments
            // that should flow together. Line breaks within text segments
            // create new lines.
            let lines = splitIntoLines(segments)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, lineSegments in
                lineView(lineSegments)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ segments: [ResponseSegment]) -> some View {
        // If the line is just a single text segment, render it as
        // attributed markdown for proper bold/italic/list rendering.
        if segments.count == 1, case .text(let text) = segments[0] {
            attributedText(text)
        } else {
            // Mixed line — flow text and code chips together.
            FlowLayout(spacing: 2) {
                ForEach(segments) { segment in
                    switch segment {
                    case .text(let text):
                        attributedText(text)
                    case .code(let code):
                        codeChip(code)
                    }
                }
            }
        }
    }

    private func attributedText(_ text: String) -> some View {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let view: Text = {
            if let attributed = try? AttributedString(markdown: text, options: options) {
                return Text(attributed)
            }
            return Text(text)
        }()

        return Group {
            if isStreaming {
                view
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                view
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
    }

    private func codeChip(_ code: String) -> some View {
        CodeSpanChip(code: code, onCopy: onCopy)
    }

    /// Split segments into lines based on newline characters inside text
    /// segments. Code segments stay on whatever line they appear in.
    private func splitIntoLines(_ segments: [ResponseSegment]) -> [[ResponseSegment]] {
        var lines: [[ResponseSegment]] = [[]]

        for segment in segments {
            switch segment {
            case .text(let text):
                let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, part) in parts.enumerated() {
                    if i > 0 {
                        lines.append([])
                    }
                    let str = String(part)
                    if !str.isEmpty {
                        lines[lines.count - 1].append(.text(str))
                    }
                }
            case .code:
                lines[lines.count - 1].append(segment)
            }
        }

        return lines.filter { !$0.isEmpty }
    }
}

// MARK: - Code span chip

/// A styled inline chip for a code span with a small copy button.
private struct CodeSpanChip: View {

    let code: String
    let onCopy: (String) -> Void
    @State private var showCheck = false

    var body: some View {
        HStack(spacing: 3) {
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Button {
                onCopy(code)
                showCheck = true
                Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    showCheck = false
                }
            } label: {
                Image(systemName: showCheck ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(showCheck ? .green.opacity(0.8) : .white.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(code)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Flow layout

/// A simple flow layout that wraps children to the next line when they
/// exceed the available width. Used to mix text and code chips inline.
private struct FlowLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }
}
