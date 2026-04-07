//
//  WidgetsSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Widget enable/disable toggles and drag-to-reorder priority list.
///
/// Uses a pure-offset approach: the `ForEach` source array is **never
/// mutated** during a drag. The dragged row follows the finger via
/// `dragTranslation`, and displaced rows slide out of the way via
/// animated ±rowHeight offsets. The array is committed once on drop.
struct WidgetsSettingsTab: View {

    @Bindable var settings: AppSettings

    /// The widget currently being dragged, if any.
    @State private var draggingWidget: WidgetID?

    /// Raw vertical translation from the drag gesture.
    @State private var dragTranslation: CGFloat = 0

    /// Height of a single row, measured once via GeometryReader.
    @State private var rowHeight: CGFloat = 40

    /// The slot the dragged item should land in. Updated with hysteresis.
    @State private var targetSlot: Int?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(settings.widgetOrder.enumerated()), id: \.element) { index, widget in
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
                        .offset(y: yOffset(at: index, isDragging: isDragging))
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

                        if widget != settings.widgetOrder.last {
                            Divider().padding(.leading, 36)
                                .opacity(draggingWidget == nil ? 1 : 0)
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

    // MARK: - Offset calculation

    /// Returns the y-offset for the row at `index`.
    /// - Dragged row: follows the finger directly (`dragTranslation`).
    /// - Displaced rows: shift ±rowHeight to make room.
    /// - All others: 0.
    private func yOffset(at index: Int, isDragging: Bool) -> CGFloat {
        if isDragging {
            return dragTranslation
        }

        guard let dragIndex = draggingWidget.flatMap({ settings.widgetOrder.firstIndex(of: $0) }),
              let target = targetSlot else {
            return 0
        }

        if dragIndex < target {
            // Dragging down: rows between origin+1…target shift up.
            if index > dragIndex && index <= target {
                return -rowHeight
            }
        } else if dragIndex > target {
            // Dragging up: rows between target…origin-1 shift down.
            if index >= target && index < dragIndex {
                return rowHeight
            }
        }

        return 0
    }

    // MARK: - Drag logic

    private func handleDragChanged(widget: WidgetID, translation: CGFloat) {
        if draggingWidget == nil {
            draggingWidget = widget
            targetSlot = settings.widgetOrder.firstIndex(of: widget)
        }
        guard draggingWidget == widget else { return }

        dragTranslation = translation

        guard let dragIndex = settings.widgetOrder.firstIndex(of: widget),
              let currentTarget = targetSlot else { return }

        let count = settings.widgetOrder.count

        // Walk from the *current* target slot toward the finger position.
        // Computing relative to the current slot (not the origin) gives
        // built-in hysteresis: after snapping, the finger must travel
        // another half-row from the new slot before the next swap.
        var newTarget = currentTarget
        var offset = translation - CGFloat(newTarget - dragIndex) * rowHeight

        while offset > rowHeight * 0.5, newTarget < count - 1 {
            newTarget += 1
            offset = translation - CGFloat(newTarget - dragIndex) * rowHeight
        }
        while offset < -rowHeight * 0.5, newTarget > 0 {
            newTarget -= 1
            offset = translation - CGFloat(newTarget - dragIndex) * rowHeight
        }

        if newTarget != currentTarget {
            withAnimation(.easeInOut(duration: 0.15)) {
                targetSlot = newTarget
            }
        }
    }

    private func handleDragEnded() {
        guard let draggingWidget,
              let dragIndex = settings.widgetOrder.firstIndex(of: draggingWidget),
              let target = targetSlot else {
            self.draggingWidget = nil
            dragTranslation = 0
            targetSlot = nil
            return
        }

        // Commit the reorder and animate everything to its final position.
        withAnimation(.easeOut(duration: 0.15)) {
            if target != dragIndex {
                var newOrder = settings.widgetOrder
                newOrder.remove(at: dragIndex)
                newOrder.insert(draggingWidget, at: target)
                settings.widgetOrder = newOrder
            }
            self.draggingWidget = nil
            dragTranslation = 0
            targetSlot = nil
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
