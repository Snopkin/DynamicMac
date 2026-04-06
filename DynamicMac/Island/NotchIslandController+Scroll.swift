//
//  NotchIslandController+Scroll.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import AppKit
import DynamicNotchKit
import Foundation
import os

/// Trackpad-scroll cycling for the widget pager. Lives in its own file
/// so `NotchIslandController.swift` stays focused on hover state and the
/// DynamicNotchKit lifecycle. Sibling to `+Chain.swift` and `+Attention.swift`.
///
/// The island's pager can be cycled two ways:
///
/// 1. The chevron buttons inside `IslandRouterView` (SwiftUI).
/// 2. A two-finger trackpad swipe while the cursor is hovering the
///    expanded panel — handled here.
///
/// ## Why two monitors
///
/// A SwiftUI `NSViewRepresentable` cannot implement (2) because AppKit
/// delivers `scrollWheel:` to a window's **first responder** and walks
/// the responder chain *upward* from there — a background
/// `NSViewRepresentable` is never on that path.
///
/// Using `NSEvent.addLocalMonitorForEvents` alone is also not enough.
/// Local monitors only see events AppKit has already dispatched to one
/// of **this** application's windows, and DNK's panel is a floating
/// non-activating `NSPanel` that does **not** become key on hover —
/// only on click. While the user is just hovering the expanded island,
/// scroll events under the cursor are not dispatched to our panel at
/// all (they go to whichever window is actually key, usually in
/// another app), so the local monitor never fires.
///
/// The fix is to pair the local monitor with a **global** monitor.
/// Global monitors observe events bound for other applications,
/// including the "scrolling over our floating panel while another
/// app is key" case. The tradeoff is that global handlers cannot
/// consume events (`-> Void` instead of `-> NSEvent?`), but that's
/// fine here: we only need to *see* the scroll to cycle widgets;
/// the event can harmlessly continue on to whatever is beneath the
/// floating panel (there's nothing there to interact with). The
/// local monitor stays installed for the post-click case where the
/// panel has become key and global monitors don't fire.
extension NotchIslandController {

    /// Minimum horizontal scroll distance (in pixels) the user must
    /// accumulate within a single gesture before a page commit fires.
    /// Tuned to require a deliberate swipe — small hesitation pans
    /// while reading a widget do not cycle.
    private static let scrollSwipeThreshold: CGFloat = 50

    /// Install both `.scrollWheel` monitors (local + global). Called
    /// from `start()` once the notch is constructed. Idempotent —
    /// guarded against double-install in case `start()` is ever called
    /// twice.
    ///
    /// The handler is gated on the cursor being inside the expanded
    /// panel's screen frame (`notch.windowController?.window?.frame`
    /// vs `NSEvent.mouseLocation`). This is the sole "is the user
    /// looking at widgets?" signal — `intendedState` is deliberately
    /// *not* used because the hover detector flips it to `.hidden`
    /// the moment the cursor crosses from the notch strip into the
    /// expanded body, even though DNK's `.keepVisible` keeps the
    /// panel on screen.
    func installScrollMonitor() {
        if localScrollMonitor == nil {
            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self else { return event }
                if self.processScroll(event: event, source: "local") {
                    // Consumed — swallow so SwiftUI scroll views in the
                    // widget don't also react.
                    return nil
                }
                return event
            }
        }
        if globalScrollMonitor == nil {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self else { return }
                _ = self.processScroll(event: event, source: "global")
            }
        }
    }

    /// Tear down both monitors. Must be called from `shutdown()` before
    /// the controller is released — monitors installed via
    /// `addLocal/GlobalMonitorForEvents` are retained by AppKit and
    /// will keep calling into a freed `self` otherwise.
    func removeScrollMonitor() {
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
            self.localScrollMonitor = nil
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
        scrollAccumulatedDeltaX = 0
        scrollGestureCommitted = false
    }

    /// Shared scroll handler body used by both monitors. Returns `true`
    /// when the event should be considered "consumed" (the local
    /// monitor will then return `nil` to swallow it; the global
    /// monitor discards the return value since global handlers cannot
    /// consume). Returns `false` when the event is a pass-through we
    /// didn't act on — scroll happened outside the panel, wrong
    /// state, vertical-dominated pan, etc.
    ///
    /// One-swipe-one-cycle is enforced by the `scrollGestureCommitted`
    /// flag: once the threshold is crossed and a commit fires, all
    /// remaining `.changed` events and the momentum tail are swallowed
    /// until the gesture ends. A new `.began` resets the flag, so quick
    /// consecutive swipes (lift-and-re-swipe) advance immediately.
    ///
    /// `source` is just for the log line so we can tell which path
    /// drove the commit during diagnosis.
    private func processScroll(event: NSEvent, source: String) -> Bool {
        // Require trackpad / Magic Mouse continuous scroll. A stepped
        // mouse-wheel click is not what "swipe between widgets" means.
        guard event.hasPreciseScrollingDeltas else {
            return false
        }

        // Cursor must be inside the expanded panel's screen frame.
        guard let panelFrame = notch?.windowController?.window?.frame else {
            return false
        }
        let cursor = NSEvent.mouseLocation
        guard panelFrame.contains(cursor) else {
            return false
        }

        // Handle gesture boundaries: reset state on a new gesture so
        // each finger-down-to-up is independent. This is what allows
        // quick consecutive swipes — the moment fingers lift and touch
        // again, the commit flag clears and a new cycle can fire.
        switch event.phase {
        case .began, .mayBegin:
            scrollAccumulatedDeltaX = 0
            scrollGestureCommitted = false
        case .ended, .cancelled:
            scrollAccumulatedDeltaX = 0
            scrollGestureCommitted = false
            return true
        default:
            break
        }

        // After committing within this gesture, eat everything until
        // the gesture ends. This is the primary one-swipe-one-cycle
        // guard — prevents a long or fast swipe from advancing 2+
        // widgets.
        if scrollGestureCommitted {
            return true
        }

        // Momentum events (`.phase == []`, `.momentumPhase != []`)
        // arrive after the user lifts their fingers. They should never
        // trigger a new commit — they belong to the previous gesture
        // whose commit flag may have already been cleared by `.ended`.
        if event.phase == [] && event.momentumPhase != [] {
            return true
        }

        // Ignore horizontal pans dominated by vertical motion — the
        // user is probably scrolling inside the widget, not cycling.
        let absX = abs(event.scrollingDeltaX)
        let absY = abs(event.scrollingDeltaY)
        guard absX > absY * 1.5 else {
            return false
        }

        // AppKit delivers positive `scrollingDeltaX` for a rightward
        // two-finger swipe (content pans right → "previous page" in a
        // natural-scrolling paging model). Invert so positive values
        // accumulate toward "next" and the gesture matches the
        // swipe-left-to-advance convention familiar from iOS.
        scrollAccumulatedDeltaX -= event.scrollingDeltaX

        // Snapshot the enabled widget list once so a concurrent settings
        // change can't give us a stale count between threshold check
        // and the cycle() call.
        let enabledWidgets = appSettings.enabledWidgetsInPriorityOrder
        guard enabledWidgets.count > 1 else { return false }

        if scrollAccumulatedDeltaX >= Self.scrollSwipeThreshold {
            commitScrollCycle(delta: 1, count: enabledWidgets.count, source: source)
            return true
        } else if scrollAccumulatedDeltaX <= -Self.scrollSwipeThreshold {
            commitScrollCycle(delta: -1, count: enabledWidgets.count, source: source)
            return true
        }

        // Partial pan: consume so SwiftUI scroll views inside the
        // widget don't also react to it, but don't commit yet.
        return true
    }

    private func commitScrollCycle(delta: Int, count: Int, source: String) {
        scrollAccumulatedDeltaX = 0
        scrollGestureCommitted = true
        DMLog.island.debug("scroll cycle delta=\(delta) count=\(count) source=\(source, privacy: .public)")
        routerState.cycle(by: delta, count: count)
    }
}
