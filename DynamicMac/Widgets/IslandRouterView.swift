//
//  IslandRouterView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import SwiftUI

/// Routes the expanded-island content to whichever widget has the
/// highest-priority live content. Phase 2 priority order:
///
///   1. Timer (if one is active: running, paused, or finished)
///   2. Hello-world placeholder
///
/// Phase 3 will insert Now Playing above Timers when media is playing.
struct IslandRouterView: View {

    @Bindable var timerService: TimerService

    var body: some View {
        Group {
            if timerService.current != nil {
                TimerWidgetView(service: timerService)
            } else {
                HelloWorldWidgetView()
            }
        }
    }
}
