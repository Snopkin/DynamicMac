//
//  QuickAskWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Combine
import SwiftUI

/// Expanded-island UI for the AI Quick Ask widget. A text field where
/// the user types a question, with a submit button. While streaming,
/// the field is replaced with a compact thinking indicator.
struct QuickAskWidgetView: View {

    @Bindable var service: AIService

    /// Resolved transition animation passed in from `IslandRouterView`.
    let animation: SwiftUI.Animation

    /// Called when the user submits a question. The parent wires this
    /// to trigger `AIService.ask()` and show the response panel.
    let onSubmit: (String) -> Void

    /// Called when the user taps the history button.
    let onShowHistory: () -> Void

    @State private var question = ""
    @FocusState private var isFieldFocused: Bool
    @State private var placeholderIndex = 0

    private static let placeholders = [
        "Ask me anything...",
        "What's the capital of Iceland?",
        "Explain dark matter briefly",
        "Swift tip of the day?",
        "Convert 72°F to Celsius",
        "Who painted Starry Night?",
        "What does O(n log n) mean?",
        "Summarize the theory of relativity",
    ]

    /// Timer-driven placeholder rotation.
    private let placeholderTimer = Timer.publish(
        every: 4,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Group {
            if !service.hasAPIKey {
                setupHint
            } else if service.isStreaming {
                streamingState
            } else {
                askField
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(animation, value: service.isStreaming)
        .onReceive(placeholderTimer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                placeholderIndex = (placeholderIndex + 1) % Self.placeholders.count
            }
        }
    }

    // MARK: - Setup hint (no API key)

    private var setupHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("API key not configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Add your key in Settings → Quick Ask")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("API key not configured. Add your key in Settings, Quick Ask tab.")
    }

    // MARK: - Ask field

    private var askField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                // Animated placeholder.
                if question.isEmpty {
                    Text(Self.placeholders[placeholderIndex])
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .id(placeholderIndex)
                        .transition(.opacity)
                }

                TextField("", text: $question)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitQuestion()
                    }
            }

            // History button (visible when there's history).
            if !service.history.isEmpty {
                Button {
                    onShowHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show history")
            }

            Button {
                submitQuestion()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .white.opacity(0.2)
                        : .white.opacity(0.8)
                    )
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - Streaming state

    private var streamingState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)

            Text("Thinking")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    StreamingDot(delay: Double(index) * 0.15)
                }
            }

            Spacer()

            Button {
                service.cancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    // MARK: - Actions

    private func submitQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        question = ""
    }
}

// MARK: - Streaming dot

/// Pulsing dot for the "Thinking..." indicator inside the island widget.
private struct StreamingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.white.opacity(isAnimating ? 0.7 : 0.15))
            .frame(width: 5, height: 5)
            .animation(
                .easeInOut(duration: 0.45)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
