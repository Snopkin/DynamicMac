//
//  WidgetsSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Widget enable/disable toggles and drag-to-reorder priority list.
///
/// Uses a custom vertical drag gesture on each row so items reorder live
/// as the user drags — no drop-target required. `IslandRouterView` reads
/// both on every reflow, so changes apply on the next hover without a
/// relaunch.
struct WidgetsSettingsTab: View {

    @Bindable var settings: AppSettings

    @State private var draggingWidget: WidgetID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeight: CGFloat = 40

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(settings.widgetOrder.enumerated()), id: \.element) { index, widget in
                        WidgetRow(
                            widget: widget,
                            isEnabled: Binding(
                                get: { settings.widgetEnabled[widget] ?? true },
                                set: { settings.widgetEnabled[widget] = $0 }
                            ),
                            isDragging: draggingWidget == widget
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { rowHeight = geo.size.height }
                            }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(draggingWidget == widget
                                      ? Color.accentColor.opacity(0.12)
                                      : Color.clear)
                        )
                        .offset(y: draggingWidget == widget ? dragOffset : 0)
                        .zIndex(draggingWidget == widget ? 1 : 0)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if draggingWidget == nil {
                                        draggingWidget = widget
                                    }
                                    guard draggingWidget == widget else { return }
                                    dragOffset = value.translation.height

                                    // Calculate how many rows the drag has crossed.
                                    let rowsCrossed = Int((dragOffset / rowHeight).rounded())
                                    guard rowsCrossed != 0 else { return }

                                    let currentIndex = settings.widgetOrder.firstIndex(of: widget) ?? index
                                    let newIndex = min(max(currentIndex + rowsCrossed, 0),
                                                       settings.widgetOrder.count - 1)

                                    if newIndex != currentIndex {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            settings.widgetOrder.move(
                                                fromOffsets: IndexSet(integer: currentIndex),
                                                toOffset: newIndex > currentIndex ? newIndex + 1 : newIndex
                                            )
                                        }
                                        // Reset offset so it feels snappy at the new position.
                                        let steps = newIndex - currentIndex
                                        dragOffset -= CGFloat(steps) * rowHeight
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        dragOffset = 0
                                    }
                                    draggingWidget = nil
                                }
                        )

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

/// A single row in the widgets list.
private struct WidgetRow: View {

    let widget: WidgetID
    @Binding var isEnabled: Bool
    var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isEnabled) {
                Label(widget.displayName, systemImage: iconName)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDragging ? .primary : .tertiary)
        }
        .contentShape(Rectangle())
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
