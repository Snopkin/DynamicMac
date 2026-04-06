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
    private static let scrollSwipeThreshold: CGFloat = 40

    /// Minimum time between scroll-driven commits. After a commit,
    /// *all* scroll events are swallowed for this duration regardless
    /// of gesture phase. Set high enough to eat the full momentum tail
    /// that trackpads deliver after a flick (~0.5–1s). One deliberate
    /// swipe = one widget cycle.
    private static let scrollCommitCooldown: TimeInterval = 0.8

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
        scrollLastCommitAt = nil
    }

    /// Shared scroll handler body used by both monitors. Returns `true`
    /// when the event should be considered "consumed" (the local
    /// monitor will then return `nil` to swallow it; the global
    /// monitor discards the return value since global handlers cannot
    /// consume). Returns `false` when the event is a pass-through we
    /// didn't act on — scroll happened outside the panel, wrong
    /// state, vertical-dominated pan, etc.
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
        // This is the authoritative "is the user looking at widgets?"
        // signal — more reliable than `intendedState`, which the hover
        // detector flips to `.hidden` the moment the cursor crosses
        // from the notch strip into the expanded island body (DNK's
        // `.keepVisible` keeps the panel on screen during that window,
        // but our chain is already converging on hidden). If the panel
        // isn't on screen, `notch?.windowController?.window?.frame` is
        // nil or the cursor is outside it, so this gate alone covers
        // both "island is hidden" and "user is scrolling elsewhere".
        guard let panelFrame = notch?.windowController?.window?.frame else {
            return false
        }
        let cursor = NSEvent.mouseLocation
        guard panelFrame.contains(cursor) else {
            return false
        }

        // After a commit, swallow everything for the cooldown window.
        // This is the primary one-swipe-one-cycle guard. Checked before
        // phase handling or accumulation so momentum tails, late
        // `.changed` events, and even new `.began` phases that arrive
        // during the cooldown are all eaten.
        if let scrollLastCommitAt,
           Date.now.timeIntervalSince(scrollLastCommitAt) < Self.scrollCommitCooldown {
            return true
        }

        // Reset the accumulator on gesture boundaries so each discrete
        // finger-down-to-up interaction is counted on its own.
        switch event.phase {
        case .began, .mayBegin:
            scrollAccumulatedDeltaX = 0
        case .ended, .cancelled:
            scrollAccumulatedDeltaX = 0
            return true
        default:
            break
        }

        // Ignore horizontal pans dominated by vertical motion — the
        // user is probably scrolling inside the widget, not cycling.
        // 1.5× ratio matches the threshold Apple uses in their own
        // paging views.
        let absX = abs(event.scrollingDeltaX)
        let absY = abs(event.scrollingDeltaY)
        guard absX > absY * 1.5 else {
            return false
        }

        // AppKit delivers positive `scrollingDeltaX` for a rightward
        // two-finger swipe (content pans right → "previous page" in a
        // natural-scrolling paging model). Invert so positive values
        // accumulate toward "next" and the gesture matches the
        // swipe-left-to-advance convention familiar from iOS. Users
        // who prefer the opposite can flip it via the OS natural-
        // scrolling setting, which already inverts `scrollingDeltaX`.
        scrollAccumulatedDeltaX -= event.scrollingDeltaX

        let count = appSettings.enabledWidgetsInPriorityOrder.count
        guard count > 1 else { return false }

        if scrollAccumulatedDeltaX >= Self.scrollSwipeThreshold {
            commitScrollCycle(delta: 1, count: count, source: source)
            return true
        } else if scrollAccumulatedDeltaX <= -Self.scrollSwipeThreshold {
            commitScrollCycle(delta: -1, count: count, source: source)
            return true
        }

        // Partial pan: consume so SwiftUI scroll views inside the
        // widget don't also react to it, but don't commit yet.
        return true
    }

    private func commitScrollCycle(delta: Int, count: Int, source: String) {
        scrollAccumulatedDeltaX = 0
        scrollLastCommitAt = Date.now
        DMLog.island.debug("scroll cycle delta=\(delta) count=\(count) source=\(source, privacy: .public)")
        routerState.cycle(by: delta, count: count)
    }

    // Widget count is read directly from
    // `appSettings.enabledWidgetsInPriorityOrder.count` — the single
    // source of truth that both the router view and this scroll monitor
    // share. No local duplicate filter needed.
}
