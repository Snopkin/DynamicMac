//
//  LaunchAtLoginController.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation
import ServiceManagement

/// Abstraction over the OS launch-at-login API so `AppSettings` can be
/// unit tested without touching the real `SMAppService` registration.
/// The production implementation is a thin wrapper over `SMAppService.mainApp`;
/// tests inject a fake that records state in memory.
@MainActor
protocol LaunchAtLoginController {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Production launch-at-login implementation backed by
/// `SMAppService.mainApp`. Available on macOS 13+; DynamicMac targets 15.0
/// so no availability check is needed.
///
/// `register()` / `unregister()` can throw if Background Items has been
/// revoked in System Settings, or if the app is running from a path the
/// system refuses to register (common in DerivedData during development).
/// `AppSettings` catches the throw and rolls the published toggle back so
/// the UI never drifts from the real system state.
struct SystemLaunchAtLoginController: LaunchAtLoginController {

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
