//
//  Logging.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation
import os

/// Shared `os.Logger` factory. Subsystem matches the app's bundle ID so
/// `Console.app` can filter the stream cleanly; category names group by
/// subsystem within the app so a targeted filter like
/// `subsystem:com.lidor.DynamicMac category:island` shows only island
/// lifecycle events.
///
/// Usage:
///
/// ```swift
/// private let log = DMLog.island
/// log.debug("expand requested at \(point.debugDescription, privacy: .public)")
/// ```
enum DMLog {
    private static let subsystem = "com.lidor.DynamicMac"

    static let island = Logger(subsystem: subsystem, category: "island")
    static let hover = Logger(subsystem: subsystem, category: "hover")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
