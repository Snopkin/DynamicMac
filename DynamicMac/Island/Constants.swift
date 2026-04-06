//
//  Constants.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Single source of truth for all tuning knobs used by the notch island.
/// Avoids magic values scattered across views.
enum Constants {

    enum Island {
        /// Target width for expanded-state content. DynamicNotchKit's panel
        /// sizes itself around the SwiftUI view, so this drives the SwiftUI frame.
        static let expandedContentWidth: CGFloat = 360

        /// Vertical padding around expanded content.
        static let expandedVerticalPadding: CGFloat = 12

        /// Horizontal padding around expanded content.
        static let expandedHorizontalPadding: CGFloat = 20
    }

    enum Animation {
        /// The Dynamic-Island canonical spring: snappy with a barely-perceptible
        /// settle. Drives all content-level transitions inside the island.
        /// DynamicNotchKit's own expand/collapse animation runs in parallel.
        static let spring: SwiftUI.Animation = .spring(
            response: 0.35,
            dampingFraction: 0.78,
            blendDuration: 0
        )

        /// Fallback curve used when the user has enabled Reduce Motion
        /// or is in Low Power Mode.
        static let reducedMotion: SwiftUI.Animation = .easeInOut(duration: 0.15)

        /// Picks the spring or the reduced-motion curve based on whether
        /// accessibility or battery-saver preferences are asking for less
        /// motion. Widgets read both flags from SwiftUI environment /
        /// observed `PowerMonitor` and pass them through here so the
        /// decision lives in one place.
        static func islandAnimation(
            reduceMotion: Bool,
            lowPower: Bool
        ) -> SwiftUI.Animation {
            (reduceMotion || lowPower) ? reducedMotion : spring
        }
    }

    enum HoverDetector {
        /// Width of the simulated-notch hover region on Macs without a
        /// hardware notch. Roughly matches DynamicNotchKit's floating pill.
        static let simulatedNotchWidth: CGFloat = 220

        /// Height fallback when the menu bar is zero (edge case).
        static let simulatedNotchFallbackHeight: CGFloat = 32
    }

    enum Timers {
        /// How often the UI countdown refreshes while a timer is running.
        /// 1 Hz is plenty for a displayed `mm:ss` readout and keeps the
        /// main run loop idle 99% of the time.
        static let displayTickInterval: TimeInterval = 1.0

        /// Tolerance granted to the display tick so macOS can coalesce
        /// it with other wakeups. 200 ms keeps the readout smooth while
        /// letting the scheduler batch aggressively on battery.
        static let displayTickTolerance: TimeInterval = 0.2

        /// Durations offered on the idle timer widget. Minutes.
        static let presetMinutes: [Int] = [1, 5, 10, 25]

        /// How long to keep the island expanded after a timer finishes,
        /// before collapsing it back to the hover-to-expand idle state.
        static let finishedExpandedLinger: TimeInterval = 5
    }
}
