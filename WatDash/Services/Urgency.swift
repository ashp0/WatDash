//
//  Urgency.swift
//  WatDash
//

import Foundation

/// How pressing a piece of marked work is, as one number: what it's worth
/// (its share of the course grade), times the hours of work it likely still
/// needs, over the hours left to do them. A 30% midterm three days out
/// outranks a 2% quiz tomorrow; an assignment due in two hours outranks
/// both. No store, no clock: checked in Tests/Checks.swift.
enum Urgency {
    struct Entry: Identifiable, Hashable, Sendable {
        var item: AgendaItem
        var score: Double
        var isOverdue: Bool
        var id: String { item.id }
    }

    /// At or above this, an item is pressing enough to interrupt the menu
    /// bar's default (the next thing due). Roughly: the work needs a quarter
    /// of the time left, scaled by what it's worth.
    static let critical = 0.25

    /// Hours of work an item typically still needs, by kind. Deliberately
    /// coarse: it only has to rank a quiz below a midterm.
    static func effortHours(_ kind: EventKind) -> Double {
        switch kind {
        case .exam: 12
        case .test: 8
        case .assignment: 4
        case .quiz: 2
        default: 1
        }
    }

    /// Share of the course grade (0–100) assumed when the grading scheme
    /// doesn't say, e.g. for a deadline from a calendar feed.
    static func typicalWeight(_ kind: EventKind) -> Double {
        switch kind {
        case .exam: 40
        case .test: 20
        case .assignment: 4
        case .quiz: 2
        default: 1
        }
    }

    /// Open marked work, most urgent first. `weights` maps an assessment's id
    /// to its share of the course grade, as the grade engine works it out.
    static func ranked(_ agenda: [AgendaItem], weights: [UUID: Double], now: Date) -> [Entry] {
        agenda.compactMap { entry(for: $0, weight: weight(of: $0, in: weights), now: now) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.start < rhs.item.start
            }
    }

    static func entry(for item: AgendaItem, weight: Double, now: Date) -> Entry? {
        guard item.kind.isAssessment || item.kind.isDue, !item.isDone else { return nil }
        let due = dueDate(item)
        let isOverdue = due <= now
        // A quiz already being written is a class, not a to-do; one that's
        // over is simply over. Only work that was due can be late, and only
        // for as long as Today keeps it in focus.
        if isOverdue, !item.isDue || now.timeIntervalSince(due) > Focus.overdueGrace { return nil }
        // Late work counts as due this minute: as pressing as anything can be.
        let hoursLeft = max(0.25, due.timeIntervalSince(now) / 3600)
        let importance = min(6, 0.5 + weight / 10)
        return Entry(item: item, score: importance * effortHours(item.kind) / hoursLeft, isOverdue: isOverdue)
    }

    static func weight(of item: AgendaItem, in weights: [UUID: Double]) -> Double {
        if case let .assessment(id) = item.origin, let weight = weights[id] { return weight }
        return typicalWeight(item.kind)
    }

    /// When the work is due, or when a written assessment starts. An all-day
    /// deadline lasts until the end of its day.
    static func dueDate(_ item: AgendaItem) -> Date {
        item.isAllDay ? item.end : item.start
    }
}
