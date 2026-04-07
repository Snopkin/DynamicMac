//
//  QuickAskSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Quick Ask configuration. Lets the user supply their Anthropic API key
/// (stored securely in the macOS Keychain) and shows the current model.
struct QuickAskSettingsTab: View {

    @Bindable var settings: AppSettings

    @State private var apiKeyInput = ""
    @State private var showSavedFeedback = false
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your Anthropic API key to enable Quick Ask.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            saveAPIKey()
                        } label: {
                            if showSavedFeedback {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(
                            apiKeyInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }

                    if settings.quickAskHasUserKey {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)

                            Text("API key configured")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Remove", role: .destructive) {
                                showClearConfirmation = true
                            }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your key is stored securely in the macOS Keychain and never leaves your device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Model", value: AIKeyProvider.model)
            } header: {
                Text("Model")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove your API key?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removeAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Quick Ask will be disabled until a new key is added.")
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AIKeyProvider.saveUserKey(trimmed)
        settings.quickAskHasUserKey = true
        apiKeyInput = ""

        showSavedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSavedFeedback = false
        }
    }

    private func removeAPIKey() {
        AIKeyProvider.removeUserKey()
        settings.quickAskHasUserKey = false
    }
}
