//
//  AIService.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import Observation
import os

/// Streams concise answers from the Anthropic Messages API. Tokens arrive
/// one by one, powering the typewriter effect in the response panel.
///
/// The system prompt instructs Claude to answer in 1-3 sentences max,
/// keeping responses short and direct — matching the micro-interaction
/// nature of the notch island.
@Observable
@MainActor
final class AIService {

    // MARK: - Published state

    /// The response being built token-by-token. Empty when idle.
    private(set) var currentResponse = ""

    /// The question that triggered the current/last response.
    private(set) var currentQuestion = ""

    /// True while the streaming request is in flight.
    private(set) var isStreaming = false

    /// User-facing error message from the last failed request, or `nil`.
    private(set) var error: String?

    /// Rolling history of the last 10 Q&A exchanges.
    private(set) var history: [AIQAEntry] = []

    /// Index into `history` for the history navigator. `nil` means
    /// showing the live/current response.
    var historyIndex: Int?

    // MARK: - Dependencies

    private let settings: AppSettings

    // MARK: - Internal state

    private var streamTask: Task<Void, Never>?

    private static let maxHistoryCount = 10
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let maxTokens = 300
    private static let systemPrompt = """
        Answer in 1-3 sentences max. Be direct and concise. \
        No filler words, no preamble, no transitional phrases like \
        "Your options are:", "Here's how:", "You can do this by:". \
        Jump straight from context to the answer or list. \
        When listing options or steps, use a numbered list with each \
        item on its own line — never introduce the list with a \
        separate sentence. Wrap terminal commands and code in \
        backticks. Never apologize or hedge.
        """

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Public API

    /// Whether any API key is configured (BYOK, bundled, or env var).
    var hasAPIKey: Bool { AIKeyProvider.apiKey() != nil }

    /// Send a question and stream the response token by token.
    func ask(_ question: String) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        cancel()

        currentQuestion = question
        currentResponse = ""
        error = nil
        isStreaming = true
        historyIndex = nil

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.performStreamingRequest(question: question)
        }
    }

    /// Cancel an in-flight request.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if isStreaming {
            isStreaming = false
        }
    }

    /// Clear the current response (hides the response panel).
    func clearCurrentResponse() {
        cancel()
        currentResponse = ""
        currentQuestion = ""
        error = nil
        historyIndex = nil
    }

    /// Populate the current question/response from a history entry so
    /// the response panel has content to display when opened from the
    /// widget's history button.
    func restoreFromHistory(_ entry: AIQAEntry) {
        currentQuestion = entry.question
        currentResponse = entry.answer
    }

    // MARK: - Streaming

    private func performStreamingRequest(question: String) async {
        guard let apiKey = AIKeyProvider.apiKey() else {
            error = "No API key configured"
            isStreaming = false
            return
        }

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build a messages array that includes recent conversation history
        // so follow-up questions have context. Each prior exchange adds a
        // user message and an assistant message. Capped to the last 5
        // exchanges to stay well within context limits and keep latency low.
        var messages: [[String: String]] = []
        let recentHistory = history.suffix(5)
        for entry in recentHistory {
            messages.append(["role": "user", "content": entry.question])
            messages.append(["role": "assistant", "content": entry.answer])
        }
        messages.append(["role": "user", "content": question])

        let body: [String: Any] = [
            "model": AIKeyProvider.model,
            "max_tokens": Self.maxTokens,
            "stream": true,
            "system": Self.systemPrompt,
            "messages": messages
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            error = "Failed to encode request"
            isStreaming = false
            return
        }
        request.httpBody = httpBody

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                error = "API error (HTTP \(httpResponse.statusCode))"
                isStreaming = false
                DMLog.ai.error("API returned HTTP \(httpResponse.statusCode)")
                return
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                if jsonString == "[DONE]" { break }

                guard let data = jsonString.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String else {
                    continue
                }

                switch type {
                case "content_block_delta":
                    if let delta = event["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        currentResponse += text
                    }

                case "message_stop":
                    break

                case "error":
                    if let errorObj = event["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        error = message
                        DMLog.ai.error("Stream error: \(message, privacy: .public)")
                    }

                default:
                    break
                }
            }

            // Save to history on successful completion.
            if !currentResponse.isEmpty, error == nil, !Task.isCancelled {
                let entry = AIQAEntry(
                    id: UUID(),
                    question: question,
                    answer: currentResponse,
                    timestamp: Date()
                )
                history.append(entry)
                if history.count > Self.maxHistoryCount {
                    history.removeFirst(history.count - Self.maxHistoryCount)
                }
            }

        } catch is CancellationError {
            DMLog.ai.debug("Stream cancelled")
        } catch {
            if !Task.isCancelled {
                self.error = "Network error"
                DMLog.ai.error("Stream failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        isStreaming = false
    }
}
