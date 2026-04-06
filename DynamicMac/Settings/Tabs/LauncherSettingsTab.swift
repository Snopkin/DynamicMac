//
//  LauncherSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App launcher configuration. Drag-to-reorder list of user-picked apps
/// with a native `NSOpenPanel`-backed add flow. Cap is enforced at
/// `AppSettings.launcherEntriesCap` — the add button disables once the
/// list is full.
struct LauncherSettingsTab: View {

    @Bindable var settings: AppSettings
    @Bindable var launcher: AppLauncherService

    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                if settings.launcherEntries.isEmpty {
                    emptyRow
                } else {
                    List {
                        ForEach(settings.launcherEntries) { entry in
                            LauncherRow(
                                entry: entry,
                                icon: launcher.icon(for: entry)
                            ) {
                                launcher.removeEntry(id: entry.id)
                            }
                        }
                        .onMove { indices, newOffset in
                            launcher.reorder(from: indices, to: newOffset)
                        }
                    }
                    .frame(minHeight: 160)
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Drag to reorder. Add Spotify, Apple Music, or any other app you'd like one click away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Add App…") {
                        presentOpenPanel()
                    }
                    .disabled(settings.launcherEntries.count >= AppSettings.launcherEntriesCap)

                    Spacer()

                    Text("\(settings.launcherEntries.count) / \(AppSettings.launcherEntriesCap)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "Couldn't add app",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Empty row

    private var emptyRow: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
            Text("No apps yet. Click \u{201C}Add App\u{2026}\u{201D} below to pin one.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Open panel

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add App to Launcher"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let added = launcher.addEntry(from: url)
        if !added {
            if settings.launcherEntries.count >= AppSettings.launcherEntriesCap {
                alertMessage = "The launcher is full (\(AppSettings.launcherEntriesCap) apps max). Remove one first."
            } else {
                alertMessage = "That app is already in the launcher."
            }
        }
    }
}

// MARK: - Row

/// A single row in the launcher list: icon + display name + trash button.
private struct LauncherRow: View {

    let entry: AppLauncherEntry
    let icon: NSImage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(entry.displayName)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(entry.displayName)")
        }
        .padding(.vertical, 2)
    }
}
