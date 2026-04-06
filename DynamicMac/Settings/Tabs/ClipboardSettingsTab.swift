//
//  ClipboardSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Clipboard shelf configuration. Max history count, auto-expiry window,
/// ignored apps list, and a "Clear All" action.
struct ClipboardSettingsTab: View {

    @Bindable var settings: AppSettings
    @Bindable var clipboardService: ClipboardService

    @State private var newIgnoredApp = ""
    @State private var showClearConfirmation = false

    private let maxCountOptions = [10, 25, 50, 100]
    private let expiryOptions: [(label: String, interval: TimeInterval)] = [
        ("1 hour", 3600),
        ("6 hours", 21600),
        ("24 hours", 86400),
        ("Never", 0)
    ]

    var body: some View {
        Form {
            Section {
                Picker("Max history", selection: $settings.clipboardMaxCount) {
                    ForEach(maxCountOptions, id: \.self) { count in
                        Text("\(count) items").tag(count)
                    }
                }

                Picker("Auto-expire after", selection: $settings.clipboardExpireInterval) {
                    ForEach(expiryOptions, id: \.interval) { option in
                        Text(option.label).tag(option.interval)
                    }
                }
            } header: {
                Text("History")
            }

            Section {
                if settings.clipboardIgnoredApps.isEmpty {
                    Text("No apps ignored. Clipboard entries from all apps are captured.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(settings.clipboardIgnoredApps, id: \.self) { bundleID in
                            HStack {
                                Text(bundleID)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    settings.clipboardIgnoredApps.removeAll { $0 == bundleID }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(bundleID)")
                            }
                        }
                    }
                    .frame(minHeight: 80)
                }

                HStack {
                    TextField("Bundle ID (e.g. com.1password.app)", text: $newIgnoredApp)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newIgnoredApp
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              !settings.clipboardIgnoredApps.contains(trimmed) else { return }
                        settings.clipboardIgnoredApps.append(trimmed)
                        newIgnoredApp = ""
                    }
                    .disabled(
                        newIgnoredApp
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Clipboard entries from these apps will not be captured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Clear History") {
                        clipboardService.clearHistory()
                    }
                    .disabled(clipboardService.history.isEmpty)

                    Button("Clear All", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .disabled(clipboardService.allEntries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all clipboard data?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clipboardService.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all clipboard history and pinned items. This cannot be undone.")
        }
    }
}
