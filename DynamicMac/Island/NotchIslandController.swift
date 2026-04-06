//
//  NotchIslandController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import DynamicNotchKit
import os
import SwiftUI

/// Owns the `DynamicNotch` overlay plus a `NotchHoverDetector` that triggers
/// expand/hide as the cursor enters and leaves the notch region. Holds
/// the service references `IslandRouterView` reads from (timer, media,
/// pomodoro, app launcher, power monitor, settings) so the expanded
/// content can route to whichever widget has the highest-priority live
/// content, falling back to the app launcher or an inline hint.
///
/// Behavior is split across sibling extensions to keep each file focused:
///
/// - **`+Chain.swift`** — serialized expand/hide task chain, working
///   around a continuation-leak bug in DynamicNotchKit 1.0.0.
/// - **`+Hover.swift`** — enter/exit handlers with a 60 Hz cursor
///   tracker for the expanded panel body.
/// - **`+Attention.swift`** — programmatic linger on timer/pomodoro
///   completion.
/// - **`+Scroll.swift`** — trackpad swipe cycling via local + global
///   `NSEvent` monitors.
@MainActor
final class NotchIslandController {

    let timerService: TimerService
    let mediaService: MediaService
    let appSettings: AppSettings
    let powerMonitor: PowerMonitor
    let pomodoroService: PomodoroService
    let appLauncherService: AppLauncherService
    let clipboardService: ClipboardService
    let aiService: AIService

    /// Manages the floating glass panel that shows AI responses below the
    /// island. Exposed so the hover extension can include it in the
    /// interaction rect.
    let quickAskPanelController = QuickAskResponsePanelController()

    /// Shared router selection state. Owned here (not as `@State` inside
    /// `IslandRouterView`) because the trackpad-scroll `NSEvent` local
    /// monitor installed below runs outside the SwiftUI view hierarchy
    /// and must mutate the same index the view reads. Holding it on the
    /// controller also keeps the user's pager position across collapse/
    /// expand cycles even if DynamicNotchKit rebuilds its hosted view.
    let routerState = IslandRouterState()

    /// Terminal state the serialized notch chain is converging toward.
    /// Used to coalesce redundant expand/hide enqueues. Internal access
    /// so the chain extension in another file can mutate it.
    enum IntendedState { case hidden, expanded }

    /// The `DynamicNotch` instance. Internal so the chain extension can
    /// capture it strongly for the duration of each enqueued operation.
    var notch: DynamicNotch<IslandRouterView, EmptyView, EmptyView>?
    private(set) var hoverDetector: NotchHoverDetector?
    var cursorInsideNotch = false

    /// Tail of the serialized expand/hide task chain. Each new request
    /// awaits this task before running its operation and then becomes
    /// the new tail. Internal so the chain extension can read and replace
    /// it.
    var pendingNotchTask: Task<Void, Never>?

    /// The state the chain will land on after the currently-queued ops
    /// drain. Starts at `.hidden` because nothing is shown until the
    /// first expand is requested. Internal so the chain extension can
    /// read and mutate it.
    var intendedState: IntendedState = .hidden

    /// True while the chain is executing `notch.hide()`. Prevents
    /// `requestHide` from cancelling the chain during a hide — that
    /// would leak DynamicNotchKit's `withCheckedContinuation`.
    var isRunningHide = false

    /// Task token for the programmatic attention linger. Internal so the
    /// attention extension can manage it from a sibling file.
    var programmaticLingerTask: Task<Void, Never>?

    /// 30 Hz timer that polls cursor position to detect when it leaves
    /// the DNK panel body. See `+Hover.swift` for the full story.
    var panelExitTimer: Foundation.Timer?

    /// Handles returned by `NSEvent.addLocalMonitorForEvents` and
    /// `addGlobalMonitorForEvents`. Both are stored so `shutdown()` can
    /// balance the add calls — the monitors outlive the controller
    /// otherwise and keep calling into a freed `self`. The local
    /// monitor fires when a DNK panel is the key window (post-click);
    /// the global monitor fires when the cursor is over a panel that
    /// has not become key, which is the usual hover case. See
    /// `NotchIslandController+Scroll.swift` for why we need both.
    /// Written from the scroll extension.
    var localScrollMonitor: Any?
    var globalScrollMonitor: Any?

    /// Accumulated horizontal scroll distance since the last committed
    /// page change. Drives the swipe-threshold gate inside the scroll
    /// monitor handler. Reset on `.began` / `.ended` gesture phases.
    /// Mutated from `NotchIslandController+Scroll.swift`.
    var scrollAccumulatedDeltaX: CGFloat = 0

    /// Set to `true` after a scroll gesture commits a page cycle. All
    /// remaining events in the same gesture are swallowed. Cleared on
    /// the next `.began` so quick consecutive swipes work immediately.
    /// Mutated from the scroll extension.
    var scrollGestureCommitted = false

    /// Read by the attention extension to decide whether to auto-collapse
    /// once the linger expires.
    var isCursorInsideNotch: Bool { cursorInsideNotch }

    init(
        timerService: TimerService,
        mediaService: MediaService,
        appSettings: AppSettings,
        powerMonitor: PowerMonitor,
        pomodoroService: PomodoroService,
        appLauncherService: AppLauncherService,
        clipboardService: ClipboardService,
        aiService: AIService
    ) {
        self.timerService = timerService
        self.mediaService = mediaService
        self.appSettings = appSettings
        self.powerMonitor = powerMonitor
        self.pomodoroService = pomodoroService
        self.appLauncherService = appLauncherService
        self.clipboardService = clipboardService
        self.aiService = aiService
    }

    func start() {
        // Strongly capture the services so the SwiftUI view has stable
        // references even if the controller is later torn down.
        let timers = timerService
        let media = mediaService
        let settings = appSettings
        let power = powerMonitor
        let pomodoro = pomodoroService
        let launcher = appLauncherService
        let clipboard = clipboardService
        let ai = aiService
        let askPanel = quickAskPanelController
        let router = routerState
        let notch = DynamicNotch(
            hoverBehavior: [.increaseShadow],
            style: .auto
        ) {
            IslandRouterView(
                timerService: timers,
                mediaService: media,
                appSettings: settings,
                powerMonitor: power,
                pomodoroService: pomodoro,
                appLauncherService: launcher,
                clipboardService: clipboard,
                aiService: ai,
                quickAskPanelController: askPanel,
                routerState: router
            )
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

        installScrollMonitor()

        timerService.onTimerFinished = { [weak self] in
            self?.handleTimerFinished()
        }

        pomodoroService.onPhaseTransition = { [weak self] _ in
            self?.handlePomodoroPhaseTransition()
        }

        // Media changes are not currently an attention event — we let
        // users discover them via hover. Keeping the hook wired (as a
        // no-op) so a future "briefly peek on track change" behavior
        // can slot in without re-plumbing.
        mediaService.onPlaybackStateBecameActive = { /* no-op for MVP */ }

        mediaService.start()
    }

    func shutdown() {
        quickAskPanelController.dismiss()

        programmaticLingerTask?.cancel()
        programmaticLingerTask = nil
        stopPanelExitTracker()

        removeScrollMonitor()

        timerService.onTimerFinished = nil
        pomodoroService.onPhaseTransition = nil
        mediaService.onPlaybackStateBecameActive = nil
        mediaService.stop()

        hoverDetector?.stop()
        hoverDetector = nil

        // Enqueue the final hide on the serial chain so it runs after any
        // in-flight expand, then drop the notch reference. Do not cancel
        // pendingNotchTask — cancellation is the exact code path that
        // leaks DynamicNotchKit's hide continuation.
        requestHide()
        pendingNotchTask = nil
        notch = nil
    }

    // MARK: - Hover handlers
    //
    // `handleEnter` and `handleExit` live in
    // `NotchIslandController+Hover.swift`. They manage
    // `cursorInsideNotch`, `panelExitTimer`, and coordinate with
    // `programmaticLingerTask`.

    // MARK: - Programmatic attention
    //
    // The `handleTimerFinished` and `handlePomodoroPhaseTransition`
    // callbacks live in `NotchIslandController+Attention.swift` so this
    // file stays focused on hover + lifecycle. The extension reads
    // `isCursorInsideNotch` and mutates `programmaticLingerTask` to
    // coordinate with the hover handlers above.
    //
    // The `installScrollMonitor` / `removeScrollMonitor` pair and the
    // matching `handleScroll` event handler live in
    // `NotchIslandController+Scroll.swift`. They mutate `scrollMonitor`,
    // `scrollAccumulatedDeltaX`, and `scrollLastCommitAt` declared above.
}
