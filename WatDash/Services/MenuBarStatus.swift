//
//  MenuBarStatus.swift
//  WatDash
//

import Foundation

/// The one line the menu bar shows, decided from the agenda and the clock.
///
/// In order: the class you're in (with the time left), a class or written
/// assessment starting within half an hour, the most urgent marked work when
/// something is pressing (see `Urgency`), otherwise the next assignment due.
/// Office hours count as a class only when their layer is switched on.
/// No store, no clock: checked in Tests/Checks.swift.
enum MenuBarStatus {
    enum Reason: Sendable {
        case inClass, startingSoon, urgent, nextDue, clear
    }

    struct Status: Equatable, Sendable {
        var reason: Reason
        var item: AgendaItem?
        /// Empty when the menu bar shows only the icon.
        var text: String
        var symbol: String
    }

    /// A class this close counts as "now": time to head over.
    static let soon: TimeInterval = 30 * 60
    /// How far ahead "next due" looks.
    static let horizon: TimeInterval = 21 * 86_400
    /// Longest name before it's cut, so the menu bar keeps its room.
    static let maxNameLength = 28

    /// The agenda window `resolve` needs around `now`.
    static func window(around now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-Focus.overdueGrace), end: now.addingTimeInterval(horizon))
    }

    /// `agenda` must be sorted by start, as the store returns it.
    static func resolve(_ agenda: [AgendaItem], weights: [UUID: Double], now: Date,
                        officeHours: Bool = false, calendar: Calendar = .current) -> Status {
        let attended = agenda.filter { isAttended($0, officeHours: officeHours) }
        if let current = attended.first(where: { $0.contains(now) }) {
            return Status(reason: .inClass, item: current,
                          text: "\(name(current)) · \(current.end.compactCountdown(from: now)) left",
                          symbol: "graduationcap.fill")
        }
        if let next = attended.first(where: { $0.start > now }), next.start.timeIntervalSince(now) <= soon {
            return Status(reason: .startingSoon, item: next,
                          text: "\(name(next)) in \(next.start.compactCountdown(from: now))",
                          symbol: "clock")
        }
        if let top = Urgency.ranked(agenda, weights: weights, now: now).first, top.score >= Urgency.critical {
            let when = top.isOverdue ? "late" : Urgency.dueDate(top.item).compactCountdown(from: now)
            return Status(reason: .urgent, item: top.item, text: "\(name(top.item)) · \(when)",
                          symbol: top.isOverdue ? "exclamationmark.triangle" : "exclamationmark.circle")
        }
        let open = agenda.filter { ($0.kind.isAssessment || $0.kind.isDue) && !$0.isDone && Urgency.dueDate($0) > now }
        if let next = open.first(where: \.isDue) ?? open.first {
            return Status(reason: .nextDue, item: next,
                          text: "\(name(next)) · \(dayLabel(Urgency.dueDate(next), now: now, calendar: calendar))",
                          symbol: "flag")
        }
        return Status(reason: .clear, item: nil, text: "", symbol: "graduationcap")
    }

    /// Where you have to be: a class meeting, or a quiz or exam written in a
    /// room. Office hours too, when their layer is on.
    static func isAttended(_ item: AgendaItem, officeHours: Bool = false) -> Bool {
        guard !item.isAllDay else { return false }
        return item.kind.isClassMeeting || (item.kind.isSeated && !item.isDue) || (officeHours && item.kind == .officeHours)
    }

    /// "ECON 101" for a class, "CS 145 A4" for marked work, cut to fit.
    static func name(_ item: AgendaItem) -> String {
        if item.kind.isClassMeeting, let code = item.courseCode { return code }
        // "Skills challenge 2: Proposal and pitch" → "Skills challenge 2".
        var title = item.title
        if let cut = title.range(of: ":") ?? title.range(of: " — ") {
            title = String(title[..<cut.lowerBound])
        }
        title = title.trimmed
        if let code = item.courseCode,
           !title.uppercased().contains(code),
           !title.uppercased().contains(code.replacingOccurrences(of: " ", with: "")) {
            title = "\(code) \(title)"
        }
        guard title.count > maxNameLength else { return title }
        return String(title.prefix(maxNameLength - 1)).trimmed + "…"
    }

    /// "4:05 PM" today, "Tomorrow", "Fri" within the week, "Oct 14" beyond.
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.days(from: now, to: date)
        var style = Date.FormatStyle.dateTime
        style.timeZone = calendar.timeZone
        switch days {
        case ...0: return date.formatted(style.hour().minute())
        case 1: return "Tomorrow"
        case 2..<7: return date.formatted(style.weekday(.abbreviated))
        default: return date.formatted(style.month(.abbreviated).day())
        }
    }
}
