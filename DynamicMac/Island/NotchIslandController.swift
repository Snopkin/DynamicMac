//
//  NotchIslandController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import DynamicNotchKit
import SwiftUI

/// Owns the `DynamicNotch` overlay and mediates between AppKit lifecycle
/// (AppDelegate) and the SwiftUI content displayed inside the notch.
///
/// DynamicNotchKit handles hover detection, expand/collapse animation,
/// and notched-vs-simulated style selection (via `.auto`). This controller
/// simply constructs the notch, holds a strong reference so it survives
/// beyond `applicationDidFinishLaunching`, and exposes `start()` / `shutdown()`
/// hooks for the AppDelegate.
@MainActor
final class NotchIslandController {

    private var notch: DynamicNotch<HelloWorldWidgetView, EmptyView, EmptyView>?

    func start() {
        // `.auto` picks `.notch` on notched MacBooks and `.floating` on
        // everything else (external displays, non-notch Macs). Hover is
        // wired internally by DynamicNotchKit — no NSTrackingArea setup
        // needed from our side.
        notch = DynamicNotch(
            hoverBehavior: .all,
            style: .auto
        ) {
            HelloWorldWidgetView()
        }
    }

    func shutdown() {
        notch = nil
    }
}
