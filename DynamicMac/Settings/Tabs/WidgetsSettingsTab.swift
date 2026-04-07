//
//  WidgetsSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Widget enable/disable toggles and drag-to-reorder priority list.
///
/// Rows reorder visually in real time as the user drags. The underlying
/// data is only committed when the drag ends, avoiding the SwiftUI
/// re-render feedback loop that causes flickering.
struct WidgetsSettingsTab: View {

    @Bindable var settings: AppSettings

    /// The widget currently being dragged, if any.
    @State private var draggingWidget: WidgetID?

    /// Raw vertical translation from the drag gesture.
    @State private var dragTranslation: CGFloat = 0

    /// Height of a single row, measured once via GeometryReader.
    @State private var rowHeight: CGFloat = 40

    /// The display order during a drag. `nil` when idle — reads from
    /// `settings.widgetOrder` directly.
    @State private var liveOrder: [WidgetID]?

    /// The index the dragged widget has been visually moved to.
    @State private var liveIndex: Int?

    private var displayOrder: [WidgetID] {
        liveOrder ?? settings.widgetOrder
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(displayOrder.enumerated()), id: \.element) { index, widget in
                        let isDragging = draggingWidget == widget

                        WidgetRow(
                            widget: widget,
                            isEnabled: Binding(
                                get: { settings.widgetEnabled[widget] ?? true },
                                set: { settings.widgetEnabled[widget] = $0 }
                            ),
                            isDragging: isDragging
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        if geo.size.height > 10 {
                                            rowHeight = geo.size.height
                                        }
                                    }
                            }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isDragging
                                      ? Color.accentColor.opacity(0.12)
                                      : Color.clear)
                        )
                        .offset(y: isDragging ? remainingOffset : 0)
                        .zIndex(isDragging ? 1 : 0)
                        .opacity(isDragging ? 0.9 : 1)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleDragChanged(widget: widget, translation: value.translation.height)
                                }
                                .onEnded { _ in
                                    handleDragEnded()
                                }
                        )

                        if widget != displayOrder.last {
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

    // MARK: - Drag logic

    /// The leftover offset after snapping the dragged item to its new slot.
    private var remainingOffset: CGFloat {
        guard let draggingWidget,
              let originalIndex = settings.widgetOrder.firstIndex(of: draggingWidget),
              let currentIndex = liveIndex else {
            return 0
        }
        let slotsMoved = currentIndex - originalIndex
        return dragTranslation - CGFloat(slotsMoved) * rowHeight
    }

    private func handleDragChanged(widget: WidgetID, translation: CGFloat) {
        if draggingWidget == nil {
            draggingWidget = widget
            liveOrder = settings.widgetOrder
        }
        guard draggingWidget == widget else { return }

        dragTranslation = translation

        guard let sourceIndex = settings.widgetOrder.firstIndex(of: widget) else { return }

        // How many rows has the drag crossed from the original position?
        let rowsCrossed = Int((translation / rowHeight).rounded())
        let targetIndex = min(max(sourceIndex + rowsCrossed, 0),
                              settings.widgetOrder.count - 1)

        if targetIndex != liveIndex {
            var newOrder = settings.widgetOrder
            newOrder.remove(at: sourceIndex)
            newOrder.insert(widget, at: targetIndex)
            withAnimation(.easeInOut(duration: 0.15)) {
                liveOrder = newOrder
                liveIndex = targetIndex
            }
        }
    }

    private func handleDragEnded() {
        // Commit the visual order to the actual settings.
        if let finalOrder = liveOrder {
            settings.widgetOrder = finalOrder
        }
        withAnimation(.easeOut(duration: 0.15)) {
            dragTranslation = 0
            draggingWidget = nil
            liveOrder = nil
            liveIndex = nil
        }
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
