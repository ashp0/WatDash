//
//  TimeGrid.swift
//  WatDash
//

import Foundation

/// The hours the Schedule's week grid draws. It opens 8 AM–10 PM and widens
/// to fit anything earlier or later that week, so a 10 PM or 11:59 PM
/// deadline is never drawn past the bottom edge. No store, no clock: checked
/// in Tests/Checks.swift.
enum TimeGrid {
    static let defaultHours = 8..<22
    /// Room a deadline marker takes on the grid, since it has no end time.
    static let dueFootprint: TimeInterval = 25 * 60

    /// Whole hours covering every timed item, never narrower than `base`.
    static func hours(for items: [AgendaItem], calendar: Calendar, base: Range<Int> = defaultHours) -> Range<Int> {
        var lower = base.lowerBound
        var upper = base.upperBound
        for item in items where !item.isAllDay {
            let dayStart = calendar.startOfDay(for: item.start)
            let end = item.isDue ? item.start.addingTimeInterval(dueFootprint) : item.end
            lower = min(lower, Int((item.start.timeIntervalSince(dayStart) / 3600).rounded(.down)))
            upper = max(upper, Int((end.timeIntervalSince(dayStart) / 3600).rounded(.up)))
        }
        return max(0, lower)..<min(24, upper)
    }
}
