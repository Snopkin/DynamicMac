//
//  AppDelegate.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit

/// Lifecycle owner for DynamicMac. Hosts the menu bar status item and,
/// in later phases, the notch overlay controller and injected services.
/// Phase 0 scope: menu bar presence only — no overlay, no services.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
