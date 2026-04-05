//
//  NSScreen+NotchGeometry.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit

/// Derives the rectangle that should act as the hover "catcher" for the
/// notch island. On a MacBook with a real hardware notch this matches the
/// physical notch cutout. On non-notched Macs we fall back to a narrow
/// strip at the top-center of the screen, mirroring DynamicNotchKit's
/// floating-style layout.
extension NSScreen {

    /// True when this screen is a notched MacBook built-in display.
    var dmHasHardwareNotch: Bool {
        auxiliaryTopLeftArea?.width != nil && auxiliaryTopRightArea?.width != nil
    }

    /// The rect to catch hovers over the notch or the simulated-notch zone,
    /// in this screen's own coordinate space (bottom-left origin).
    ///
    /// Layout rationale: we make the hover region exactly the notch/strip
    /// cutout so the cursor must actually reach the notch to trigger the
    /// island. `hoverBehavior: .keepVisible` on the DynamicNotch then keeps
    /// the island open while the cursor is on the expanded content.
    var dmHoverRect: NSRect {
        if let notchRect = dmNotchRect {
            return notchRect
        }

        let width: CGFloat = Constants.HoverDetector.simulatedNotchWidth
        let height: CGFloat = max(menubarHeight, Constants.HoverDetector.simulatedNotchFallbackHeight)

        return NSRect(
            x: frame.midX - (width / 2),
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Notch cutout in screen coordinates, or `nil` when there is no notch.
    private var dmNotchRect: NSRect? {
        guard
            let leftPadding = auxiliaryTopLeftArea?.width,
            let rightPadding = auxiliaryTopRightArea?.width
        else {
            return nil
        }
        let height = safeAreaInsets.top
        let width = frame.width - leftPadding - rightPadding
        return NSRect(
            x: frame.midX - (width / 2),
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Height of the menu bar on this screen.
    private var menubarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }
}
