//
//  WidgetsSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Widget enable/disable toggles and drag-to-reorder priority list.
///
/// The list shows every known `WidgetID` in the user's chosen order. A
/// checkbox on each row writes through `AppSettings.widgetEnabled`; rows
/// are reordered via native drag-and-drop (`.draggable` / `.dropDestination`).
/// `IslandRouterView` reads both on every reflow, so changes apply on the
/// next hover without a relaunch.
struct WidgetsSettingsTab: View {

    @Bindable var settings: AppSettings
    @State private var draggingWidget: WidgetID?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    ForEach(settings.widgetOrder) { widget in
                        WidgetRow(
                            widget: widget,
                            isEnabled: Binding(
                                get: { settings.widgetEnabled[widget] ?? true },
                                set: { settings.widgetEnabled[widget] = $0 }
                            )
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(draggingWidget == widget
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .draggable(widget.rawValue) {
                            WidgetDragPreview(widget: widget)
                                .onAppear { draggingWidget = widget }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first,
                                  let source = WidgetID(rawValue: raw),
                                  source != widget else { return false }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                move(source, before: widget)
                            }
                            return true
                        } isTargeted: { targeted in
                            if !targeted, draggingWidget != nil {
                                // Keep highlight only on the current drop target.
                            }
                        }

                        if widget != settings.widgetOrder.last {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .onChange(of: draggingWidget) { _, _ in }
            } header: {
                Text("Priority")
            } footer: {
                Text("Drag to reorder. Widgets higher in the list win when more than one has live content.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ source: WidgetID, before target: WidgetID) {
        guard let sourceIndex = settings.widgetOrder.firstIndex(of: source),
              let targetIndex = settings.widgetOrder.firstIndex(of: target) else { return }
        settings.widgetOrder.remove(at: sourceIndex)
        let insertIndex = settings.widgetOrder.firstIndex(of: target) ?? settings.widgetOrder.endIndex
        settings.widgetOrder.insert(source, at: insertIndex)
        draggingWidget = nil
    }
}

/// A single row in the widgets list. Shown as `Toggle` so macOS renders
/// the native inline checkbox style inside a `List` on Sequoia/Tahoe.
private struct WidgetRow: View {

    let widget: WidgetID
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isEnabled) {
                Label(widget.displayName, systemImage: iconName)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var iconName: String {
        switch widget {
        case .timer: return "timer"
        case .nowPlaying: return "music.note"
        case .pomodoro: return "leaf.fill"
        case .appLauncher: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .quickAsk: return "sparkles"
        }
    }
}

/// Translucent preview shown under the cursor during a drag.
private struct WidgetDragPreview: View {

    let widget: WidgetID

    var body: some View {
        Label(widget.displayName, systemImage: iconName)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch widget {
        case .timer: return "timer"
        case .nowPlaying: return "music.note"
        case .pomodoro: return "leaf.fill"
        case .appLauncher: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .quickAsk: return "sparkles"
        }
    }
}
