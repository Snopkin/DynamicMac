//
//  QuickAskResponsePanelController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import Combine
import os
import SwiftUI

/// Owns the floating dark panel that displays AI responses below the
/// island. Positioned centered beneath the notch, at `.floating` level
/// (below DynamicNotchKit's `.screenSaver` panel, above normal windows).
///
/// The panel auto-dismisses after the cursor has been outside it for 10
/// seconds. A countdown ring around the close button visualizes the
/// remaining time. Moving the cursor back over the panel resets the timer.
@MainActor
final class QuickAskResponsePanelController {

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    /// Exposed so `NotchIslandController+Hover` can extend the
    /// interaction rect to include the response panel.
    var panelFrame: NSRect { panel?.frame ?? .zero }

    /// Whether the panel is currently on screen.
    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Auto-dismiss countdown

    /// How long (seconds) the panel waits after cursor exit before
    /// auto-dismissing.
    private static let autoDismissDelay: TimeInterval = 10

    /// 1.0 = full (no countdown), 0.0 = about to dismiss.
    /// Bound to the countdown ring in `QuickAskResponseView`.
    private var countdownProgress: Double = 1.0

    /// Published wrapper so SwiftUI can bind to it.
    private let countdownSubject = CurrentValueSubject<Double, Never>(1.0)

    private var cursorTracker: Timer?
    private var countdownTimer: Timer?
    private var countdownStart: Date?

    /// Callback invoked when auto-dismiss fires. Set by the caller
    /// (IslandRouterView) so it can also clear AIService state.
    var onAutoDismiss: (() -> Void)?

    /// Returns the island's expanded interaction rect so the cursor
    /// tracker can treat the notch area as "inside". Set by
    /// `NotchIslandController` after construction.
    var islandInteractionRect: (() -> NSRect?)?

    // MARK: - Show / Update / Dismiss

    /// Show the response panel below the island with the given SwiftUI
    /// content. If the panel already exists, updates its content in place.
    func show<Content: View>(content: Content) {
        let wrappedContent = AnyView(content)

        if let hostingController {
            hostingController.rootView = wrappedContent
            panel?.makeKeyAndOrderFront(nil)
            resetCountdown()
            startCursorTracker()
            return
        }

        let hosting = NSHostingController(rootView: wrappedContent)
        hosting.view.frame = NSRect(x: 0, y: 0, width: Constants.Island.quickAskResponseWidth, height: 80)
        hostingController = hosting

        let panel = ResponsePanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.Island.quickAskResponseWidth, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting

        positionBelowIsland(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Fade in.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        resetCountdown()
        startCursorTracker()

        DMLog.ai.debug("Response panel shown at \(NSStringFromRect(panel.frame), privacy: .public)")
    }

    /// Update the panel's size to fit its content. Called when the
    /// streaming response grows. The top edge stays pinned; the panel
    /// extends downward.
    func updateSize() {
        guard let panel, let hostingController else { return }

        let fittingSize = hostingController.view.fittingSize
        let clampedHeight = min(
            max(fittingSize.height, 60),
            Constants.Island.quickAskResponseMaxHeight
        )
        let clampedWidth = Constants.Island.quickAskResponseWidth

        // Pin the top edge, extend downward.
        let topY = panel.frame.maxY
        let newFrame = NSRect(
            x: panel.frame.midX - clampedWidth / 2,
            y: topY - clampedHeight,
            width: clampedWidth,
            height: clampedHeight
        )

        panel.setFrame(newFrame, display: true, animate: false)
    }

    /// Fade out and remove the panel.
    func dismiss() {
        stopCursorTracker()
        stopCountdown()

        guard let panel else { return }

        // Nil out references immediately so a subsequent `show()` call
        // during the fade-out animation creates a fresh panel instead
        // of trying to reuse the one that's being dismissed.
        self.panel = nil
        self.hostingController = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    /// A `Binding<Double>` that SwiftUI views can use to show the
    /// countdown ring. Driven by `countdownSubject`.
    func makeCountdownBinding() -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.countdownSubject.value ?? 1.0 },
            set: { _ in }
        )
    }

    // MARK: - Cursor tracking

    private func startCursorTracker() {
        stopCursorTracker()
        let timer = Timer(timeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCursorCheck()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTracker = timer
    }

    private func stopCursorTracker() {
        cursorTracker?.invalidate()
        cursorTracker = nil
    }

    private func tickCursorCheck() {
        guard let panel, panel.isVisible else {
            stopCursorTracker()
            return
        }

        let cursor = NSEvent.mouseLocation

        // Check if cursor is inside the response panel (with comfort margin)
        // OR inside the island's expanded interaction rect (notch + content).
        let panelHitRect = panel.frame.insetBy(dx: -10, dy: -10)
        let insidePanel = panelHitRect.contains(cursor)
        let insideIsland = islandInteractionRect?()?.contains(cursor) ?? false
        let cursorInside = insidePanel || insideIsland

        if cursorInside {
            if countdownStart != nil {
                resetCountdown()
            }
        } else {
            if countdownStart == nil {
                startCountdown()
            }
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownStart = Date()
        stopCountdown()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func resetCountdown() {
        stopCountdown()
        countdownStart = nil
        countdownSubject.send(1.0)
    }

    private func tickCountdown() {
        guard let start = countdownStart else {
            stopCountdown()
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, 1.0 - elapsed / Self.autoDismissDelay)
        countdownSubject.send(remaining)

        if remaining <= 0 {
            stopCountdown()
            stopCursorTracker()
            onAutoDismiss?()
        }
    }

    // MARK: - Positioning

    /// Center the panel below the island's interaction rect with a small
    /// gap. Uses the same screen geometry as the hover detector.
    private func positionBelowIsland(_ panel: NSPanel) {
        let screen = NSScreen.primaryWithNotchOrMain
        let strip = screen.dmHoverRect

        // The island's visible bottom: notch strip top - content height - DNK safe area.
        let islandContentHeight: CGFloat = 80
        let dnkSafeArea: CGFloat = 15
        let islandBottom = strip.maxY - strip.height - islandContentHeight - dnkSafeArea
        let gap: CGFloat = 2

        let panelWidth = Constants.Island.quickAskResponseWidth
        let panelHeight = panel.frame.height
        let panelX = strip.midX - panelWidth / 2
        let panelY = islandBottom - gap - panelHeight

        panel.setFrame(
            NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            display: false
        )
    }
}

// MARK: - Panel subclass

/// Non-focus-stealing panel for the response overlay. Allows key events
/// to pass through to the hosting view for accessibility but doesn't
/// steal focus from the foreground app.
private final class ResponsePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
