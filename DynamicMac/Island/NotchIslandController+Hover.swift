//
//  NotchIslandController+Hover.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import DynamicNotchKit
import os

/// Hover enter/exit handlers, plus a timer-driven cursor tracker for
/// the expanded panel body.
///
/// Architecture overview:
///
/// `NotchHoverDetector` owns a thin NSPanel over the notch strip.
/// When the cursor enters → `handleEnter` → `requestExpand()`.
/// When the cursor exits the strip into the expanded body,
/// `mouseExited` fires but the user is still inside the island. We
/// detect this by checking a computed "interaction rect" (the visible
/// content area, NOT the oversized DNK window frame). A 30 Hz timer
/// polls the cursor position; the instant it leaves → `requestHide()`.
///
/// DynamicNotchKit sizes its window at half the screen dimensions and
/// uses a SwiftUI mask to clip to the notch shape — the window frame
/// is useless for hit-testing. We derive the interaction rect from the
/// notch strip geometry + our known content height.
extension NotchIslandController {

    // MARK: - Interaction rect

    /// The visible content area of the expanded island, in screen
    /// coordinates. Covers the notch strip plus the expanded content
    /// body below it, with generous horizontal margins so the cursor
    /// can move freely without prematurely triggering a hide.
    ///
    /// Returns `nil` if no screen geometry is available.
    var expandedInteractionRect: NSRect? {
        let screen = NSScreen.primaryWithNotchOrMain
        let strip = screen.dmHoverRect

        // The expanded content lives below the notch strip. Its height
        // is variable (depends on which widget is showing) but we can
        // use a generous estimate. DNK's NotchView adds safeAreaInsets
        // (15pt each side) plus the notch height at top.
        let contentHeight: CGFloat = 120
        let dnkSafeArea: CGFloat = 15

        // Width: our content is 340pt but DNK adds corner radii,
        // safe-area insets, and padding. Use the strip width extended
        // generously on each side.
        let interactionWidth = max(strip.width, Constants.Island.expandedContentWidth) + 70
        let interactionHeight = strip.height + contentHeight + dnkSafeArea

        var rect = NSRect(
            x: strip.midX - interactionWidth / 2,
            y: strip.maxY - interactionHeight,
            width: interactionWidth,
            height: interactionHeight
        )

        // Extend to include the Quick Ask response panel if visible, so
        // the island stays open while the user reads the AI answer.
        if quickAskPanelController.isVisible {
            let panelFrame = quickAskPanelController.panelFrame
            let unionMinY = min(rect.minY, panelFrame.minY)
            rect = NSRect(
                x: min(rect.minX, panelFrame.minX),
                y: unionMinY,
                width: max(rect.maxX, panelFrame.maxX) - min(rect.minX, panelFrame.minX),
                height: rect.maxY - unionMinY
            )
        }

        return rect
    }

    // MARK: - Hover handlers

    func handleEnter() {
        let cursor = NSEvent.mouseLocation
        let ts = DispatchTime.now().uptimeNanoseconds

        DMLog.island.debug("[\(ts)] handleEnter cursorInside=\(self.cursorInsideNotch) intended=\(String(describing: self.intendedState), privacy: .public) cursor=\(NSStringFromPoint(cursor), privacy: .public)")

        cursorInsideNotch = true

        programmaticLingerTask?.cancel()
        programmaticLingerTask = nil
        stopPanelExitTracker()

        requestExpand()
    }

    func handleExit() {
        let cursor = NSEvent.mouseLocation
        let ts = DispatchTime.now().uptimeNanoseconds

        DMLog.island.debug("[\(ts)] handleExit cursorInside=\(self.cursorInsideNotch) intended=\(String(describing: self.intendedState), privacy: .public) cursor=\(NSStringFromPoint(cursor), privacy: .public)")

        cursorInsideNotch = false

        guard programmaticLingerTask == nil else {
            DMLog.island.debug("[\(ts)] handleExit — programmatic linger active, skipping")
            return
        }

        // Check if cursor is inside the visible content area (not the
        // oversized DNK window frame).
        if let interactionRect = expandedInteractionRect {
            if interactionRect.contains(cursor) {
                DMLog.island.debug("[\(ts)] handleExit — cursor inside interaction rect \(NSStringFromRect(interactionRect), privacy: .public), starting exit tracker")
                startPanelExitTracker()
                return
            }
            DMLog.island.debug("[\(ts)] handleExit — cursor OUTSIDE interaction rect \(NSStringFromRect(interactionRect), privacy: .public)")
        }

        requestHide()
    }

    // MARK: - Panel exit tracker (60 Hz timer)

    func startPanelExitTracker() {
        stopPanelExitTracker()
        let timer = Foundation.Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickPanelExitCheck()
        }
        RunLoop.main.add(timer, forMode: .common)
        panelExitTimer = timer
    }

    func stopPanelExitTracker() {
        panelExitTimer?.invalidate()
        panelExitTimer = nil
    }

    private func tickPanelExitCheck() {
        guard !cursorInsideNotch else {
            stopPanelExitTracker()
            return
        }

        guard let interactionRect = expandedInteractionRect else {
            let ts = DispatchTime.now().uptimeNanoseconds
            DMLog.island.debug("[\(ts)] exit tracker — no interaction rect, requesting hide")
            stopPanelExitTracker()
            requestHide()
            return
        }

        let cursor = NSEvent.mouseLocation
        if !interactionRect.contains(cursor) {
            let ts = DispatchTime.now().uptimeNanoseconds
            DMLog.island.debug("[\(ts)] exit tracker — cursor \(NSStringFromPoint(cursor), privacy: .public) left interaction rect \(NSStringFromRect(interactionRect), privacy: .public), requesting hide")
            stopPanelExitTracker()
            requestHide()
        }
    }

}
