//
//  Dates.swift
//  WatDash
//

import Foundation

/// Waterloo time. Course pages, outlines and Quest all speak it, so anything
/// parsed from them is interpreted here regardless of where the Mac is.
enum Waterloo {
    static let timeZone = TimeZone(identifier: "America/Toronto") ?? .current

    /// Odyssey's personal assessment schedule: every in-person quiz, midterm
    /// and final with its room and assigned seat (posted ~3 business days before).
    static let seatingURL = URL(string: "https://odyssey.uwaterloo.ca/teaching/schedule")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2  // Monday, like every UW timetable
        calendar.locale = Locale(identifier: "en_CA")
        return calendar
    }
}

extension Calendar {
    /// Monday-first week containing `date`.
    func startOfWeek(for date: Date) -> Date {
        var calendar = self
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func days(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }
}

extension Date {
    /// "2h 14m" / "35m" / "3d 4h".
    func compactCountdown(from reference: Date = .now) -> String {
        let seconds = Int(timeIntervalSince(reference))
        guard seconds > 0 else { return "now" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days >= 1 {
            let remainingHours = hours % 24
            return remainingHours > 0 && days < 4 ? "\(days)d \(remainingHours)h" : "\(days)d"
        }
        if hours >= 1 {
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
        return "\(max(1, minutes))m"
    }

    var shortTime: String { formatted(date: .omitted, time: .shortened) }

    var relativeDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let days = calendar.days(from: .now, to: self)
        if days > 0 && days < 7 { return formatted(.dateTime.weekday(.wide)) }
        return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var dayMonth: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
