//
//  Event.swift
//  WatDash
//

import Foundation

/// What an entry on the timetable *is*. Drives its icon, colour treatment,
/// whether holidays cancel it, and whether it counts as a deadline.
enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case lecture, tutorial, lab, seminar
    case quiz, test, exam
    case assignment, deadline
    case officeHours, event, holiday, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lecture: "Lecture"
        case .tutorial: "Tutorial"
        case .lab: "Lab"
        case .seminar: "Seminar"
        case .quiz: "Quiz"
        case .test: "Midterm / test"
        case .exam: "Exam"
        case .assignment: "Assignment"
        case .deadline: "Deadline"
        case .officeHours: "Office hours"
        case .event: "Event"
        case .holiday: "No classes"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .lecture: "person.3.sequence"
        case .tutorial: "person.2"
        case .lab: "flask"
        case .seminar: "bubble.left.and.bubble.right"
        case .quiz: "checklist"
        case .test: "pencil.and.list.clipboard"
        case .exam: "graduationcap"
        case .assignment: "doc.text"
        case .deadline: "flag"
        case .officeHours: "door.left.hand.open"
        case .event: "star"
        case .holiday: "sun.max"
        case .other: "circle"
        }
    }

    /// Scheduled class meetings. Only these are cancelled by holidays and
    /// reading week — a deadline during reading week still stands.
    var isClassMeeting: Bool {
        switch self {
        case .lecture, .tutorial, .lab, .seminar: true
        default: false
        }
    }

    /// Things that are marked and therefore matter to the grade engine.
    var isAssessment: Bool {
        switch self {
        case .quiz, .test, .exam, .assignment: true
        default: false
        }
    }

    /// Point-in-time items (due at 4:05 PM) rather than blocks of time.
    var isDue: Bool { self == .assignment || self == .deadline }

    /// Quest / outline component codes → kind.
    static func fromComponent(_ code: String?) -> EventKind? {
        switch code?.uppercased() {
        case "LEC": .lecture
        case "TUT": .tutorial
        case "LAB": .lab
        case "SEM": .seminar
        case "TST": .test
        default: nil
        }
    }
}

/// RFC 5545 subset: enough for weekly timetables and one-off exceptions.
struct Recurrence: Codable, Hashable, Sendable {
    enum Frequency: String, Codable, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    var frequency: Frequency
    var interval: Int = 1
    var count: Int?
    var until: Date?
    /// `Calendar` weekday numbers (1 = Sunday). Empty means "the start's weekday".
    var weekdays: [Int] = []

    static func weekly(on weekdays: [Int], until: Date?) -> Recurrence {
        Recurrence(frequency: .weekly, interval: 1, count: nil, until: until, weekdays: weekdays)
    }

    var summary: String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var parts: [String] = []
        switch frequency {
        case .daily: parts.append(interval == 1 ? "Daily" : "Every \(interval) days")
        case .weekly:
            let days = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.compactMap { (1...7).contains($0) ? names[$0] : nil }
            let every = interval == 1 ? "Weekly" : "Every \(interval) weeks"
            parts.append(days.isEmpty ? every : "\(every) on \(days.joined(separator: ", "))")
        case .monthly: parts.append("Monthly")
        case .yearly: parts.append("Yearly")
        }
        if let until { parts.append("until \(until.formatted(.dateTime.month(.abbreviated).day()))") }
        if let count { parts.append("× \(count)") }
        return parts.joined(separator: " ")
    }
}

/// Confidence-gated automation: imports from structured sources land as
/// `confirmed`; guesses (quick capture from messy text, email) can land as
/// `proposed` and wait in the inbox for a one-click yes.
enum EventStatus: String, Codable, Sendable {
    case confirmed, proposed, cancelled
}

/// One entry in the canonical store. Recurring entries are stored once and
/// expanded on demand (see `RecurrenceExpander`).
struct DashEvent: Identifiable, Codable, Hashable, Sendable {
    /// Stable across re-imports: "<source id>:<uid>" for imported events, so
    /// importing the same file twice updates instead of duplicating.
    var id: String
    var title: String
    var courseCode: String?
    var kind: EventKind
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var location: String?
    var notes: String?
    var url: String?
    var recurrence: Recurrence?
    var exceptionDates: [Date] = []
    var timeZoneID: String?
    var sourceID: UUID?
    var status: EventStatus = .confirmed
    /// Reading week, statutory holidays: suppresses class meetings that day.
    var cancelsClasses: Bool = false
    var isHidden: Bool = false
    var createdAt: Date = .now

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    var timeZone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}

/// A concrete, dated thing to show: one expanded event occurrence or one
/// dated assessment. Views and widgets only ever see these.
struct AgendaItem: Identifiable, Hashable, Sendable {
    enum Origin: Hashable, Sendable {
        case event(String)
        case assessment(UUID)
    }

    var id: String
    var origin: Origin
    var title: String
    var courseCode: String?
    var kind: EventKind
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var detail: String?
    var isDone: Bool = false

    var isDue: Bool { kind.isDue || (kind.isAssessment && end <= start) }

    func contains(_ date: Date) -> Bool { start <= date && date < end }
}
