//
//  AppLauncherWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import SwiftUI

/// Expanded-island UI for the app launcher widget. Horizontal row of up
/// to 6 user-picked app icons. Hover shows the app's display name as a
/// macOS native tooltip; click launches/activates the app via
/// `AppLauncherService.launch(_:)`.
///
/// 34pt icons × 6 entries + 5 × 10pt gaps = 254pt, comfortably inside
/// the 320pt usable island content width. Empty state renders a short
/// hint instead of leaving the island visually blank.
struct AppLauncherWidgetView: View {

    @Bindable var service: AppLauncherService

    /// Resolved transition animation passed in from `IslandRouterView`.
    let animation: SwiftUI.Animation

    var body: some View {
        Group {
            if service.entries.isEmpty {
                emptyState
            } else {
                launcherRow
            }
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .animation(animation, value: service.entries)
    }

    // MARK: - Populated row

    private var launcherRow: some View {
        HStack(spacing: 10) {
            ForEach(service.entries) { entry in
                LauncherIconButton(
                    entry: entry,
                    icon: service.icon(for: entry)
                ) {
                    service.launch(entry)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App launcher")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            Text("Add apps in Settings")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App launcher empty. Add apps in Settings.")
    }
}

// MARK: - Launcher button

/// A single clickable app icon. 34pt rounded-rect thumbnail with a
/// subtle hover scale, a native `.help()` tooltip carrying the app's
/// display name, and an accessibility label prefixed with "Launch" so
/// VoiceOver announces intent clearly.
private struct LauncherIconButton: View {

    let entry: AppLauncherEntry
    let icon: NSImage
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(entry.displayName)
        .accessibilityLabel("Launch \(entry.displayName)")
    }
}
