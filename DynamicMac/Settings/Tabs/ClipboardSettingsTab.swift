//
//  ClipboardSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard shelf configuration. Max history count, auto-expiry window,
/// ignored apps list, and a "Clear All" action.
struct ClipboardSettingsTab: View {

    @Bindable var settings: AppSettings
    @Bindable var clipboardService: ClipboardService

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
                    ForEach(settings.clipboardIgnoredApps, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            appIcon(for: bundleID)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(for: bundleID))
                                    .lineLimit(1)
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                settings.clipboardIgnoredApps.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(appName(for: bundleID))")
                        }
                    }
                }

                Button {
                    pickApp()
                } label: {
                    Label("Add App...", systemImage: "plus")
                }
                .buttonStyle(.borderless)
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

    // MARK: - App picker

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to ignore"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }

        if !settings.clipboardIgnoredApps.contains(bundleID) {
            settings.clipboardIgnoredApps.append(bundleID)
        }
    }

    // MARK: - App metadata helpers

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        // Fallback: use the last component of the bundle ID.
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    private func appIcon(for bundleID: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
