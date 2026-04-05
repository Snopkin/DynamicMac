//
//  NotchHoverDetector.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit

/// Detects when the cursor enters and leaves the notch region.
///
/// DynamicNotchKit only creates its overlay panel after `expand()` is called
/// — it does not listen for cursor-over-notch to open itself. We therefore
/// keep a thin, always-visible, transparent NSPanel over the notch cutout
/// (or a simulated strip on non-notched Macs) with an NSTrackingArea that
/// fires enter/exit callbacks. The callbacks drive `DynamicNotch.expand()` /
/// `DynamicNotch.hide()` in `NotchIslandController`.
///
/// The detector panel sits at `.statusBar` level (above the menu bar) so
/// cursor events reach it, but below DynamicNotchKit's `.screenSaver`-level
/// panel so the expanded island draws on top.
@MainActor
final class NotchHoverDetector {

    private var panel: NSPanel?
    private var screenChangeObserver: NSObjectProtocol?

    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
    }

    func start() {
        installPanel()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The .main OperationQueue guarantees this fires on the main
            // thread; hop to the MainActor for isolation checking.
            Task { @MainActor in
                self?.installPanel()
            }
        }
    }

    func stop() {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel construction

    private func installPanel() {
        panel?.orderOut(nil)
        panel = nil

        let screen = NSScreen.primaryWithNotchOrMain
        let frame = screen.dmHoverRect

        let panel = HoverDetectorPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrame(frame, display: false)

        let trackingView = HoverTrackingView(onEnter: onEnter, onExit: onExit)
        trackingView.frame = NSRect(origin: .zero, size: frame.size)
        trackingView.autoresizingMask = [.width, .height]
        panel.contentView = trackingView

        panel.orderFrontRegardless()
        self.panel = panel
    }
}

// MARK: - Panel subclass

/// Non-focus-stealing, non-accessible NSPanel for the hover detector.
/// Returning `false` from `canBecomeKey`/`canBecomeMain` prevents the
/// detector from stealing focus from the foreground app and keeps it out
/// of the UI test runner's window-hierarchy scans.
private final class HoverDetectorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Tracking view

/// NSView subclass that owns the NSTrackingArea and bridges mouseEntered /
/// mouseExited to plain closures.
private final class HoverTrackingView: NSView {

    private let onEnter: () -> Void
    private let onExit: () -> Void
    private var trackingArea: NSTrackingArea?

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }

    override func mouseExited(with event: NSEvent) {
        onExit()
    }
}

// MARK: - NSScreen selection

extension NSScreen {
    /// Picks the best screen to host the hover detector: the notched built-in
    /// screen if present, otherwise the main screen.
    static var primaryWithNotchOrMain: NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.dmHasHardwareNotch }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}
