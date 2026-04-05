//
//  IslandRouterView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Routes the expanded-island content to whichever widget has the
/// highest-priority live content. Phase 3 priority order:
///
///   1. Timer (if one is active: running, paused, or finished)
///   2. Now Playing (if anything is playing anywhere on the system)
///   3. Hello-world placeholder
///
/// The ordering is intentional: timers are ephemeral and demand
/// attention, so they win over persistent background music.
struct IslandRouterView: View {

    @Bindable var timerService: TimerService
    @Bindable var mediaService: MediaService

    var body: some View {
        Group {
            if timerService.current != nil {
                TimerWidgetView(service: timerService)
            } else if mediaService.current != nil {
                NowPlayingWidgetView(service: mediaService)
            } else {
                HelloWorldWidgetView()
            }
        }
    }
}
