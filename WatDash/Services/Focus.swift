//
//  Focus.swift
//  WatDash
//

import Foundation

/// What the Today screen puts first: marked work that is late or lands in
/// the next two days, plus midterms and exams in the coming week (they need
/// study time, not just a reminder). No store, no clock: the windows are
/// checked in Tests/Checks.swift.
enum Focus {
    enum Urgency: Int, Sendable {
        case overdue, within24h, within48h, examThisWeek
    }

    struct Entry: Identifiable, Hashable, Sendable {
        var item: AgendaItem
        var urgency: Urgency
        var id: String { item.id }
    }

    static let horizon: TimeInterval = 48 * 3600
    static let examHorizon: TimeInterval = 7 * 86_400
    /// Late work stays in focus this long (most late windows are 48 hours);
    /// after that it only shows under Deadlines → Overdue.
    static let overdueGrace: TimeInterval = 48 * 3600

    /// The agenda window `entries` needs, around `now`.
    static func window(around now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-overdueGrace), end: now.addingTimeInterval(examHorizon))
    }

    /// Most urgent first: overdue, then by time.
    static func entries(from agenda: [AgendaItem], now: Date) -> [Entry] {
        agenda.compactMap { item -> Entry? in
            guard item.kind.isAssessment || item.kind.isDue, !item.isDone else { return nil }
            let untilStart = item.start.timeIntervalSince(now)
            if item.end < now {
                // A written quiz is simply over; only work that was due is late.
                guard item.isDue, -untilStart <= overdueGrace else { return nil }
                return Entry(item: item, urgency: .overdue)
            }
            if untilStart <= 24 * 3600 { return Entry(item: item, urgency: .within24h) }
            if untilStart <= horizon { return Entry(item: item, urgency: .within48h) }
            if item.kind == .test || item.kind == .exam, untilStart <= examHorizon {
                return Entry(item: item, urgency: .examThisWeek)
            }
            return nil
        }
        .sorted { ($0.urgency.rawValue, $0.item.start) < ($1.urgency.rawValue, $1.item.start) }
    }
}
