//
//  WidgetsSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Widget enable/disable toggles and drag-to-reorder priority list.
///
/// The list shows every known `WidgetID` in the user's chosen order. A
/// checkbox on each row writes through `AppSettings.widgetEnabled`; the
/// `.onMove` handler rewrites `AppSettings.widgetOrder`. `IslandRouterView`
/// reads both on every reflow, so changes apply on the next hover without
/// a relaunch.
struct WidgetsSettingsTab: View {

    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(settings.widgetOrder) { widget in
                        WidgetRow(
                            widget: widget,
                            isEnabled: Binding(
                                get: { settings.widgetEnabled[widget] ?? true },
                                set: { settings.widgetEnabled[widget] = $0 }
                            )
                        )
                    }
                    .onMove { indices, newOffset in
                        settings.widgetOrder.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .frame(minHeight: 160)
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
}

/// A single row in the widgets list. Shown as `Toggle` so macOS renders
/// the native inline checkbox style inside a `List` on Sequoia/Tahoe.
private struct WidgetRow: View {

    let widget: WidgetID
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Label(widget.displayName, systemImage: iconName)
        }
        .toggleStyle(.checkbox)
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
