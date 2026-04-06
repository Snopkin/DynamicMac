//
//  IslandRouterState.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import Observation

/// Cross-cutting router state shared between `IslandRouterView` and
/// `NotchIslandController`. Extracted from the view's `@State` so two
/// callers can drive widget cycling:
///
///   1. The pager chevron buttons inside the SwiftUI view.
///   2. A trackpad-scroll `NSEvent` monitor installed on the controller
///      side — `NSEvent.addLocalMonitorForEvents` runs outside the
///      SwiftUI view hierarchy, so a view-local `@State` would be
///      invisible to it.
///
/// Living here also makes `selectedIndex` survive panel hide/show cycles
/// even if DynamicNotchKit rebuilds its hosted view — the state is owned
/// by the controller for the lifetime of the app, so the user's pager
/// position is preserved across collapses.
@Observable
@MainActor
final class IslandRouterState {

    /// Index into the currently-enabled widget list that the router is
    /// showing. Clamped by the view on read so a stale index from a
    /// shrunken enabled list can never render past the end.
    var selectedIndex: Int = 0

    /// Advance the selection by `delta` with wraparound. `count` is
    /// passed in because the router owns the enabled-widget list and
    /// this class is deliberately free of any `AppSettings` coupling.
    func cycle(by delta: Int, count: Int) {
        guard count > 0 else { return }
        let raw = (selectedIndex + delta) % count
        selectedIndex = raw < 0 ? raw + count : raw
    }
}
