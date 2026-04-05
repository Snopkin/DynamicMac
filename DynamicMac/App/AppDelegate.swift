//
//  AppDelegate.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit

/// Lifecycle owner for DynamicMac. Hosts the menu bar status item and
/// the notch island controller. In later phases also owns injected
/// services (TimerService, MediaService, AppSettings).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let islandController = NotchIslandController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        islandController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        islandController.shutdown()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "oval.fill",
            accessibilityDescription: "DynamicMac"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About DynamicMac",
            action: nil,
            keyEquivalent: ""
        )
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: nil,
            keyEquivalent: ","
        )
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit DynamicMac",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
