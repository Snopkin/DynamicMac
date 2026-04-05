//
//  HelloWorldWidgetView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Phase 1 placeholder content shown inside the expanded notch island.
/// Replaced in later phases by the priority-routed widget (Now Playing,
/// Timers, or the default placeholder).
struct HelloWorldWidgetView: View {

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hello, DynamicMac")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(Date.now, style: .date)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Constants.Island.expandedVerticalPadding)
        .padding(.horizontal, Constants.Island.expandedHorizontalPadding)
        .frame(width: Constants.Island.expandedContentWidth)
    }
}

#Preview {
    HelloWorldWidgetView()
        .background(Color.black)
}
