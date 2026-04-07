//
//  IslandRouterView.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import SwiftUI

/// Routes the expanded-island content to the currently-selected enabled
/// widget. Unlike the original Phase 1 router, this one does **not** gate
/// visibility on whether the widget's backing service has live content —
/// every widget has a meaningful idle state (timer preset pills, pomodoro
/// "Start Focus" button, launcher app row, "Nothing playing" slate) and
/// hiding those defeats the point of being able to start things from the
/// notch. When multiple widgets have live content, the most-recently-
/// activated one wins the initial selection (see `rebaseSelection`), and
/// when there are two or more enabled widgets a compact pager with
/// chevron buttons and paging dots is overlaid so the user can cycle
/// between them. Trackpad scroll cycling is driven by an `NSEvent` local
/// monitor installed on `NotchIslandController`, which is why the
/// selection index lives in the externally-owned `IslandRouterState`
/// rather than a view-local `@State` — the monitor runs outside the
/// SwiftUI hierarchy and must write to the same index the view reads.
///
/// Only when zero widgets are enabled does the router fall through to
/// the `EmptyHintView` nudging the user toward Settings.
struct IslandRouterView: View {

    @Bindable var timerService: TimerService
    @Bindable var mediaService: MediaService
    @Bindable var appSettings: AppSettings
    @Bindable var powerMonitor: PowerMonitor
    @Bindable var pomodoroService: PomodoroService
    @Bindable var appLauncherService: AppLauncherService
    @Bindable var clipboardService: ClipboardService
    @Bindable var aiService: AIService
    let quickAskPanelController: QuickAskResponsePanelController
    @Bindable var routerState: IslandRouterState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read the live-session properties here, inside the body, so
        // SwiftUI's `@Observable` tracking registers a dependency on
        // them at the router level. Without this, the router body only
        // observes `AppSettings` (through `enabledWidgets`) and never
        // re-runs when a timer ticks or a pomodoro advances — which
        // means the nested widget views, rendered as part of this
        // body's tree, also never re-evaluate. Reading the properties
        // unconditionally (even though we only bias the initial
        // selection off them) is what restores the 1 Hz live refresh
        // the timer/pomodoro services are already publishing.
        let currentTimer = timerService.current
        let currentPomodoro = pomodoroService.current

        return Group {
            let widgets = enabledWidgets
            if widgets.isEmpty {
                EmptyHintView()
            } else {
                pagerView(widgets: widgets)
            }
        }
        .tint(appSettings.islandTintColor)
        // The expanded island has a fixed content width and cannot be
        // resized by the user. Clamping Dynamic Type keeps widget
        // content inside its frame on accessibility text sizes instead
        // of pushing the transport buttons off the right edge.
        .dynamicTypeSize(.medium ... .xxLarge)
        .onChange(of: enabledWidgets) { _, newValue in
            rebaseSelection(for: newValue)
        }
        // When a background session *becomes* active (user started a
        // timer from a launcher app, another pomodoro fired, etc.)
        // auto-jump to that widget so the user sees what just changed.
        // Comparing to `nil` — not to the struct value — keeps this
        // from re-selecting on every 1 Hz tick.
        .onChange(of: currentTimer == nil) { _, _ in
            biasSelectionTowardLiveContent()
        }
        .onChange(of: currentPomodoro == nil) { _, _ in
            biasSelectionTowardLiveContent()
        }
        // Auto-switch to Now Playing when playback actually starts (if
        // enabled). Watches `isPlaying` rather than `current != nil` so
        // stale paused media from browser tabs does not trigger a switch.
        .onChange(of: mediaService.current?.isPlaying) { wasPlaying, isPlaying in
            if isPlaying == true, wasPlaying != true, appSettings.mediaAutoSwitchOnPlay {
                switchToNowPlaying()
            }
        }
        // On first appearance, if media is actively playing and auto-switch
        // is on, jump to Now Playing. The onChange above only fires on
        // transitions, so it misses the "already playing on launch" case.
        .onAppear {
            if mediaService.current?.isPlaying == true, appSettings.mediaAutoSwitchOnPlay {
                switchToNowPlaying()
            }
        }
        // Keep the response panel sized to fit the streaming content.
        .onChange(of: aiService.currentResponse) { _, _ in
            if quickAskPanelController.isVisible {
                quickAskPanelController.updateSize()
            }
        }
        // Dismiss the response panel when the response is cleared while
        // idle. Guard on `!isStreaming` so that a follow-up question
        // (which briefly resets currentResponse to "") does not kill the
        // panel before the new stream has a chance to fill it.
        .onChange(of: aiService.currentResponse.isEmpty) { _, isEmpty in
            if isEmpty, !aiService.isStreaming {
                quickAskPanelController.dismiss()
            }
        }
    }

    /// Resolved animation for all widget-level transitions. Swaps to a
    /// gentle ease curve when either the system Reduce Motion setting
    /// or Low Power Mode is active.
    private var islandAnimation: SwiftUI.Animation {
        Constants.Animation.islandAnimation(
            reduceMotion: reduceMotion,
            lowPower: powerMonitor.isLowPowerModeActive
        )
    }

    // MARK: - Enabled widget list

    /// User-ordered list of enabled widgets with all runtime gates
    /// applied. Single source of truth lives in `AppSettings` — do not
    /// duplicate the filter here.
    private var enabledWidgets: [WidgetID] {
        appSettings.enabledWidgetsInPriorityOrder
    }

    // MARK: - Pager shell

    @ViewBuilder
    private func pagerView(widgets: [WidgetID]) -> some View {
        let safeIndex = min(max(routerState.selectedIndex, 0), widgets.count - 1)
        let widget = widgets[safeIndex]

        VStack(spacing: 4) {
            content(for: widget)
                .id(widget) // force SwiftUI to treat each widget as a distinct subtree
                .transition(.opacity)

            if widgets.count > 1 {
                pagerControls(widgets: widgets, currentIndex: safeIndex)
            }
        }
        .animation(islandAnimation, value: safeIndex)
        // Trackpad-scroll cycling is handled by an `NSEvent` local monitor
        // installed on `NotchIslandController`, not by a SwiftUI-hosted
        // NSViewRepresentable. The monitor approach is necessary because
        // AppKit delivers `scrollWheel:` to the window's first responder
        // (the SwiftUI hosting view) rather than hit-testing to the view
        // under the cursor — so a `.background { NSViewRepresentable }`
        // never sees the events at all. The local monitor intercepts
        // before dispatch, reads the cursor position, and mutates
        // `routerState.selectedIndex` directly. See
        // `NotchIslandController.installScrollMonitor()`.
    }

    private func pagerControls(widgets: [WidgetID], currentIndex: Int) -> some View {
        HStack(spacing: 10) {
            pagerButton(
                systemName: "chevron.left",
                accessibilityLabel: "Previous widget"
            ) {
                routerState.cycle(by: -1, count: widgets.count)
            }

            HStack(spacing: 5) {
                ForEach(widgets.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex
                              ? Color.white.opacity(0.85)
                              : Color.white.opacity(0.20))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)

            pagerButton(
                systemName: "chevron.right",
                accessibilityLabel: "Next widget"
            ) {
                routerState.cycle(by: 1, count: widgets.count)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pagerButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Selection management

    /// Pick a sensible starting widget when the enabled list (re)appears.
    ///
    /// The selection rule has two tiers:
    ///
    /// 1. If any widget has live content (running timer, running pomodoro,
    ///    playing media), prefer the one the user most recently activated
    ///    — compared via `lastActivationDate`. This is the tiebreaker that
    ///    stops a long-running background pomodoro from beating a timer
    ///    the user just pressed start on, even though pomodoro ranks
    ///    higher in the priority order.
    /// 2. If no widget has live content, keep the current index if it is
    ///    still in range; otherwise fall back to zero (the first widget
    ///    in the user's priority order).
    ///
    /// `appLauncher` and `nowPlaying` don't expose a `lastActivationDate`
    /// of their own: the launcher is session-less, and media "activation"
    /// is driven by apps outside DynamicMac's control. They participate
    /// in the first-tier match purely on the "has content" flag and lose
    /// the tiebreaker to any widget with a real timestamp, which matches
    /// the user's mental model ("I just started a timer" beats "Spotify
    /// happens to be playing").
    private func rebaseSelection(for widgets: [WidgetID]) {
        guard !widgets.isEmpty else {
            routerState.selectedIndex = 0
            return
        }
        if let preferred = preferredLiveContentIndex(in: widgets) {
            routerState.selectedIndex = preferred
        } else if routerState.selectedIndex >= widgets.count {
            routerState.selectedIndex = 0
        }
    }

    /// Called when a background session becomes active (or clears) so
    /// the router jumps to the newly-relevant widget without forcing
    /// the user to cycle. No-op if the currently-selected widget is
    /// already the one with live content — cycling mid-session should
    /// not yank the user back on every tick.
    private func biasSelectionTowardLiveContent() {
        let widgets = enabledWidgets
        guard !widgets.isEmpty else { return }
        guard let preferred = preferredLiveContentIndex(in: widgets) else { return }
        let currentIndex = min(max(routerState.selectedIndex, 0), widgets.count - 1)
        if routerState.selectedIndex != preferred, !hasLiveContent(for: widgets[currentIndex]) {
            routerState.selectedIndex = preferred
        }
    }

    /// Returns the index of the widget with live content that the user
    /// most recently activated, or `nil` when no enabled widget has live
    /// content. Widgets without an activation timestamp (launcher, media)
    /// still participate but are ranked below any widget that does — see
    /// `rebaseSelection` for the full policy.
    private func preferredLiveContentIndex(in widgets: [WidgetID]) -> Int? {
        var best: (index: Int, activatedAt: Date)?
        for (index, widget) in widgets.enumerated() where hasLiveContent(for: widget) {
            let activatedAt = activationDate(for: widget) ?? .distantPast
            if let current = best {
                if activatedAt > current.activatedAt {
                    best = (index, activatedAt)
                }
            } else {
                best = (index, activatedAt)
            }
        }
        return best?.index
    }

    /// Whether the widget's backing service currently has something
    /// time-sensitive to show. Used only to bias the initial selection —
    /// widgets without live content are still rendered (in their idle
    /// state) and remain fully reachable via the pager chevrons.
    private func hasLiveContent(for widget: WidgetID) -> Bool {
        switch widget {
        case .timer:
            return timerService.current != nil
        case .nowPlaying:
            return mediaService.isRecentlyActive
        case .pomodoro:
            return pomodoroService.current != nil
        case .appLauncher:
            return !appLauncherService.entries.isEmpty
        case .clipboard:
            return !clipboardService.allEntries.isEmpty
        case .quickAsk:
            return aiService.isStreaming || !aiService.currentResponse.isEmpty
        }
    }

    /// Wall-clock timestamp of the user's most recent activation of this
    /// widget, if the backing service tracks one. Only timer and pomodoro
    /// have an explicit "user pressed start" moment that makes sense to
    /// tiebreak on; launcher and media return `nil` and tiebreak as
    /// `distantPast`.
    private func activationDate(for widget: WidgetID) -> Date? {
        switch widget {
        case .timer:
            return timerService.lastActivationDate
        case .pomodoro:
            return pomodoroService.lastActivationDate
        case .nowPlaying, .appLauncher, .clipboard, .quickAsk:
            return nil
        }
    }

    /// Jump to the Now Playing widget if it's enabled.
    private func switchToNowPlaying() {
        let widgets = enabledWidgets
        guard let index = widgets.firstIndex(of: .nowPlaying) else { return }
        routerState.selectedIndex = index
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for widget: WidgetID) -> some View {
        switch widget {
        case .timer:
            TimerWidgetView(service: timerService, animation: islandAnimation)
        case .nowPlaying:
            NowPlayingWidgetView(service: mediaService, animation: islandAnimation)
        case .pomodoro:
            PomodoroWidgetView(
                service: pomodoroService,
                settings: appSettings,
                animation: islandAnimation
            )
        case .appLauncher:
            AppLauncherWidgetView(
                service: appLauncherService,
                animation: islandAnimation
            )
        case .clipboard:
            ClipboardWidgetView(
                service: clipboardService,
                animation: islandAnimation
            )
        case .quickAsk:
            QuickAskWidgetView(
                service: aiService,
                animation: islandAnimation,
                onSubmit: { question in
                    handleQuickAskSubmit(question)
                },
                onShowHistory: {
                    handleQuickAskShowHistory()
                }
            )
        }
    }

    // MARK: - Quick Ask

    private func handleQuickAskSubmit(_ question: String) {
        aiService.ask(question)
        showResponsePanel()
    }

    /// Show the response panel (for both new questions and history browsing).
    private func showResponsePanel() {
        let responseView = QuickAskResponseView(
            service: aiService,
            onClose: { [quickAskPanelController, aiService] in
                quickAskPanelController.dismiss()
                aiService.clearCurrentResponse()
            },
            onCopy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            countdownProgress: quickAskPanelController.makeCountdownBinding()
        )
        quickAskPanelController.onAutoDismiss = { [quickAskPanelController, aiService] in
            quickAskPanelController.dismiss()
            aiService.clearCurrentResponse()
        }
        quickAskPanelController.show(content: responseView)
    }

    /// Open the response panel showing history. Called from the widget's
    /// history button.
    private func handleQuickAskShowHistory() {
        guard !aiService.history.isEmpty else { return }
        // Point to the last history entry.
        aiService.historyIndex = aiService.history.count - 1
        // Populate currentQuestion/Response from the last entry so the
        // panel has something to show.
        if aiService.currentResponse.isEmpty {
            let last = aiService.history.last!
            aiService.restoreFromHistory(last)
        }
        showResponsePanel()
    }
}
