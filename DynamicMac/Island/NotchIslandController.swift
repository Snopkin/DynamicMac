//
//  NotchIslandController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import DynamicNotchKit
import SwiftUI

/// Owns the `DynamicNotch` overlay plus a `NotchHoverDetector` that triggers
/// expand/hide as the cursor enters and leaves the notch region.
///
/// DynamicNotchKit's `init` only registers the notch; it does not create any
/// NSPanel or listen for hovers until `expand()` is called. The hover
/// detector bridges that gap with an always-on thin NSPanel + NSTrackingArea.
/// `hoverBehavior: .keepVisible` on the notch keeps the island open while
/// the cursor is inside the expanded content, so a brief cursor exit from
/// the notch strip into the expanded island area does not dismiss the view.
@MainActor
final class NotchIslandController {

    private var notch: DynamicNotch<HelloWorldWidgetView, EmptyView, EmptyView>?
    private var hoverDetector: NotchHoverDetector?

    func start() {
        // `.auto` picks `.notch` on notched MacBooks and `.floating` on
        // external displays and non-notched Macs.
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto
        ) {
            HelloWorldWidgetView()
        }
        self.notch = notch

        let detector = NotchHoverDetector(
            onEnter: { [weak self] in
                self?.handleEnter()
            },
            onExit: { [weak self] in
                self?.handleExit()
            }
        )
        detector.start()
        self.hoverDetector = detector
    }

    func shutdown() {
        hoverDetector?.stop()
        hoverDetector = nil

        if let notch {
            Task { @MainActor in
                await notch.hide()
            }
        }
        notch = nil
    }

    // MARK: - Hover handlers

    private func handleEnter() {
        guard let notch else { return }
        Task { @MainActor in
            await notch.expand()
        }
    }

    private func handleExit() {
        guard let notch else { return }
        Task { @MainActor in
            await notch.hide()
        }
    }
}
