//
//  EmptyHintView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import SwiftUI

/// Rendered only when the user has disabled every widget in Settings.
/// Replaces the old `HelloWorldWidgetView` fallback with something that
/// actually guides the user toward action.
struct EmptyHintView: View {

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)

            Text("Enable a widget in Settings")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No widgets enabled. Enable one in Settings.")
    }
}
