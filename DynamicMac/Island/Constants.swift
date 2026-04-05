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

        /// Fallback curve used when the user has enabled Reduce Motion.
        static let reducedMotion: SwiftUI.Animation = .easeInOut(duration: 0.15)
    }
}
