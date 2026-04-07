//
//  QuickAskResponseView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Dark response panel content for the AI Quick Ask feature.
/// Shows the streaming answer with a typewriter cursor, a copy button,
/// a history navigator, and a countdown ring around the close button
/// that auto-dismisses the panel when the cursor leaves for 10 seconds.
struct QuickAskResponseView: View {

    @Bindable var service: AIService
    let onClose: () -> Void
    let onCopy: (String) -> Void

    @State private var showCopiedCheck = false

    /// Countdown progress (1.0 → 0.0) driven by the panel controller
    /// when the cursor leaves.
    @Binding var countdownProgress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Show the question when browsing history.
            if isShowingHistory, !displayedQuestion.isEmpty {
                questionHeader
                Divider().opacity(0.15)
            }

            responseBody

            if service.history.count > 1 || !displayedAnswer.isEmpty {
                Divider().opacity(0.15)
                actionBar
            }
        }
        .frame(width: Constants.Island.quickAskResponseWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }

    // MARK: - Question header (history only)

    private var questionHeader: some View {
        Text(displayedQuestion)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    // MARK: - Response text

    private var responseBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let error = service.error, service.historyIndex == nil {
                    errorView(error)
                } else if !displayedAnswer.isEmpty {
                    markdownText(displayedAnswer, isStreaming: isStreamingCurrent)
                } else if isStreamingCurrent {
                    thinkingDots
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Action bar (copy, history nav, close)

    private var actionBar: some View {
        HStack(spacing: 6) {
            // Copy button.
            Button {
                let text = displayedAnswer
                guard !text.isEmpty else { return }
                onCopy(text)
                showCopiedCheck = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    showCopiedCheck = false
                }
            } label: {
                Image(systemName: showCopiedCheck ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(showCopiedCheck ? .green.opacity(0.7) : .white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy answer")
            .disabled(displayedAnswer.isEmpty)

            Spacer()

            // History navigator (only when there's history).
            if service.history.count > 1 {
                Button {
                    navigateHistory(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(canNavigateBack ? 0.5 : 0.15))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigateBack)

                Text(historyPositionLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))

                Button {
                    navigateHistory(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(canNavigateForward ? 0.5 : 0.15))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigateForward)
            }

            Spacer()

            // Close button with countdown ring.
            Button(action: onClose) {
                ZStack {
                    if countdownProgress < 1.0 {
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: countdownProgress)
                            .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .frame(width: 16, height: 16)
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// Render response text with inline markdown while preserving line
    /// breaks. Code spans (backtick-wrapped) are rendered as styled
    /// inline chips with a small copy button next to them.
    private func markdownText(_ text: String, isStreaming: Bool) -> some View {
        let displayText = isStreaming ? text + "▍" : text
        let segments = ResponseTextParser.parse(displayText)

        return ResponseSegmentsView(
            segments: segments,
            isStreaming: isStreaming,
            onCopy: onCopy
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange.opacity(0.8))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Thinking dots

    private var thinkingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                ThinkingDot(delay: Double(index) * 0.15)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - History navigator

    private var historyNavigator: some View {
        HStack(spacing: 10) {
            Button {
                navigateHistory(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateBack)

            Text(historyPositionLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                navigateHistory(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateForward)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Display helpers

    /// The answer currently being displayed — either from history or live.
    private var displayedAnswer: String {
        if let idx = service.historyIndex, idx < service.history.count {
            return service.history[idx].answer
        }
        return service.currentResponse
    }

    /// Whether we're browsing history (not showing the live response).
    private var isShowingHistory: Bool {
        service.historyIndex != nil
    }

    /// The question currently being displayed.
    private var displayedQuestion: String {
        if let idx = service.historyIndex, idx < service.history.count {
            return service.history[idx].question
        }
        return service.currentQuestion
    }

    /// Whether the current display is the live streaming response.
    private var isStreamingCurrent: Bool {
        service.historyIndex == nil && service.isStreaming
    }

    /// Whether the live response is a duplicate of the last history entry
    /// (i.e. streaming just finished and the response was saved to history).
    private var isLiveDuplicateOfHistory: Bool {
        guard !service.currentResponse.isEmpty,
              let last = service.history.last else { return false }
        return last.answer == service.currentResponse
    }

    private var historyPositionLabel: String {
        // Only count a separate "live" slot if the response is actively
        // streaming or if it differs from the last history entry (i.e. it
        // hasn't been saved to history yet). This prevents the same
        // completed answer from appearing as both "N/N" and "(N-1)/N".
        let liveSlot = (!service.currentResponse.isEmpty && !isLiveDuplicateOfHistory) ? 1 : 0
        let total = service.history.count + liveSlot
        let current: Int
        if let idx = service.historyIndex {
            current = idx + 1
        } else {
            // Showing the live response — its position is the last.
            current = total
        }
        guard total > 0 else { return "0/0" }
        return "\(current)/\(total)"
    }

    private var canNavigateBack: Bool {
        if let idx = service.historyIndex {
            return idx > 0
        }
        // When the live response duplicates the last history entry, we're
        // effectively already showing the last history item. Navigate back
        // only if there's a *previous* history entry.
        if isLiveDuplicateOfHistory {
            return service.history.count > 1
        }
        return !service.history.isEmpty
    }

    private var canNavigateForward: Bool {
        if let idx = service.historyIndex {
            let maxIndex = service.history.count - 1
            let hasDistinctLive = !service.currentResponse.isEmpty && !isLiveDuplicateOfHistory
            return idx < maxIndex || (idx == maxIndex && hasDistinctLive)
        }
        return false
    }

    private func navigateHistory(by offset: Int) {
        if let idx = service.historyIndex {
            let newIndex = idx + offset
            let maxHistoryIndex = service.history.count - 1
            if newIndex < 0 {
                return
            } else if newIndex > maxHistoryIndex {
                // Jump to live response only if it's distinct from history.
                if !isLiveDuplicateOfHistory {
                    service.historyIndex = nil
                }
            } else {
                service.historyIndex = newIndex
            }
        } else {
            // Currently showing live — can only go back.
            if offset < 0, !service.history.isEmpty {
                // If live duplicates history, skip past the last entry.
                let targetIndex = isLiveDuplicateOfHistory
                    ? service.history.count - 2
                    : service.history.count - 1
                if targetIndex >= 0 {
                    service.historyIndex = targetIndex
                }
            }
        }
    }
}

// MARK: - Thinking dot

/// A single dot in the "thinking" indicator. Pulses opacity with a
/// staggered delay to create the iMessage-style typing animation.
private struct ThinkingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.white.opacity(isAnimating ? 0.8 : 0.2))
            .frame(width: 6, height: 6)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Blinking cursor modifier

private struct BlinkingCursorModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true),
                value: visible
            )
            .onAppear { visible = false }
    }
}

extension View {
    func blinkingCursor() -> some View {
        modifier(BlinkingCursorModifier())
    }
}
