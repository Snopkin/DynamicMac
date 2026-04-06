//
//  ClipboardWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import SwiftUI

/// Expanded-island UI for the clipboard shelf widget. Shows pinned items
/// first, then the most recent history entries, up to 5 rows total.
/// Each row offers a re-copy button and a pin/unpin toggle.
struct ClipboardWidgetView: View {

    @Bindable var service: ClipboardService

    /// Resolved transition animation passed in from `IslandRouterView`.
    let animation: SwiftUI.Animation

    /// Brief checkmark feedback after re-copying an entry.
    @State private var copiedEntryID: UUID?

    var body: some View {
        Group {
            if service.allEntries.isEmpty {
                emptyState
            } else {
                clipboardList
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(animation, value: service.allEntries.map(\.id))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            Text("Copy something to get started")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clipboard shelf empty. Copy something to get started.")
    }

    // MARK: - Clip list

    private var clipboardList: some View {
        VStack(spacing: 4) {
            ForEach(service.allEntries.prefix(5)) { entry in
                clipRow(entry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard shelf")
    }

    private func clipRow(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            clipPreview(entry)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Pin / unpin toggle.
            Button {
                if entry.isPinned {
                    service.unpin(entry)
                } else {
                    service.pin(entry)
                }
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(entry.isPinned ? 0.9 : 0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isPinned ? "Unpin" : "Pin")

            // Re-copy button with checkmark feedback.
            Button {
                service.recopy(entry)
                copiedEntryID = entry.id
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    if copiedEntryID == entry.id {
                        copiedEntryID = nil
                    }
                }
            } label: {
                Image(systemName: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private func clipPreview(_ entry: ClipboardEntry) -> some View {
        switch entry.content {
        case .text(let string):
            Text(string)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

        case .url(let url):
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

        case .image(let data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
