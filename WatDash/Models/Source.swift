//
//  Source.swift
//  WatDash
//

import Foundation

/// Where data came from. Every event and assessment points back at one, which
/// is what makes "why is this on my calendar?" answerable and re-imports
/// idempotent: re-running a source replaces exactly what it produced before.
struct DataSource: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case icsFile, icsFeed, questPaste, outline, courseFolder, openData, holidays, appleCalendar, quickCapture, manual, demo

        var label: String {
            switch self {
            case .icsFile: "Calendar file"
            case .icsFeed: "Calendar feed"
            case .questPaste: "Quest schedule"
            case .outline: "Course outline"
            case .courseFolder: "Course folder"
            case .openData: "Waterloo Open Data"
            case .holidays: "UW holidays"
            case .appleCalendar: "Apple Calendar"
            case .quickCapture: "Quick capture"
            case .manual: "Added by hand"
            case .demo: "Sample term"
            }
        }

        var symbol: String {
            switch self {
            case .icsFile: "doc.badge.clock"
            case .icsFeed: "antenna.radiowaves.left.and.right"
            case .questPaste: "list.clipboard"
            case .outline: "doc.richtext"
            case .courseFolder: "folder"
            case .openData: "building.columns"
            case .holidays: "sun.max"
            case .appleCalendar: "calendar"
            case .quickCapture: "bolt"
            case .manual: "hand.point.up.left"
            case .demo: "sparkles"
            }
        }

        /// Sources that can be re-fetched without the user doing anything.
        var isRefreshable: Bool {
            switch self {
            case .icsFeed, .courseFolder, .openData, .holidays, .appleCalendar: true
            default: false
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var name: String
    /// URL for feeds, path for files/folders, calendar ids for Apple Calendar.
    var location: String?
    var calendarIdentifiers: [String] = []
    var lastRefresh: Date?
    var lastError: String?
    var itemCount: Int = 0
    var isEnabled: Bool = true

    var health: Health {
        if lastError != nil { return .failing }
        guard kind.isRefreshable, let lastRefresh else { return .ok }
        return Date.now.timeIntervalSince(lastRefresh) > 3 * 86_400 ? .stale : .ok
    }

    enum Health { case ok, stale, failing }
}

/// A seat you're waiting for (e.g. the Russian section you want as a sixth
/// course), polled through the Open Data API.
struct SeatWatch: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var courseCode: String
    var section: String  // "001", or "" for any LEC
    var capacity: Int?
    var enrolled: Int?
    var lastChecked: Date?
    var lastNotifiedOpen: Bool = false

    var openSeats: Int? {
        guard let capacity, let enrolled else { return nil }
        return max(0, capacity - enrolled)
    }
}
