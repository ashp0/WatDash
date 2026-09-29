//
//  Logging.swift
//  WatDash
//

import Foundation
import os

/// Central log handles, readable in Console.app under the app's subsystem.
enum Log {
    private static let subsystem = "com.ashwinpaudel.WatDash"

    static let store = Logger(subsystem: subsystem, category: "Store")
    static let importer = Logger(subsystem: subsystem, category: "Import")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let study = Logger(subsystem: subsystem, category: "Study")
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
}
