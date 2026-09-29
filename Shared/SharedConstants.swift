//
//  SharedConstants.swift
//  WatDash
//

import Foundation

/// Identifiers both processes must agree on. The App Group id comes from the
/// Info.plist (baked in by Tools/generate_project.py) so it always matches the
/// signing team, instead of being a second hardcoded copy that can drift.
enum SharedConstants {
    static let appGroup: String = {
        (Bundle.main.object(forInfoDictionaryKey: "WatDashAppGroup") as? String)
            ?? "3AML23Y649.com.ashwinpaudel.WatDash"
    }()

    static let snapshotFileName = "widget-snapshot.json"
    static let urlScheme = "watdash"

    /// Where the app writes, and the widget reads, the snapshot.
    static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}
