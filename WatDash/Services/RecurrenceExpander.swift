//
//  RecurrenceExpander.swift
//  WatDash
//

import Foundation

/// Expands stored events into dated occurrences for a window.
///
/// Pure (no clock reads, no store access) so the time-dependent parts — DST,
/// exceptions, holiday suppression — are covered by Tests/Checks.swift.
///
/// Occurrences are generated in the event's own time zone, so a 10:30 Waterloo
/// lecture stays at 10:30 local across the November DST change.
enum RecurrenceExpander {

    /// Safety cap: no timetable needs more, and a malformed RRULE must not spin.
    private static let maxIterations = 2_000

    static func occurrences(of event: DashEvent, in window: DateInterval) -> [DateInterval] {
        let duration = event.duration
        guard let rule = event.recurrence else {
            let interval = DateInterval(start: event.start, end: max(event.end, event.start))
            return overlaps(interval, window) ? [interval] : []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZone
        calendar.firstWeekday = 2

        let exceptions = event.exceptionDates
        func isException(_ date: Date) -> Bool {
            exceptions.contains { exception in
                event.isAllDay
                    ? calendar.isDate(exception, inSameDayAs: date)
                    : abs(exception.timeIntervalSince(date)) < 60
            }
        }

        let time = calendar.dateComponents([.hour, .minute, .second], from: event.start)
        var results: [DateInterval] = []
        var produced = 0

        func consider(_ start: Date) -> Bool {
            // Returns false when the series is finished.
            if let until = rule.until, start > until.addingTimeInterval(event.isAllDay ? 86_399 : 59) { return false }
            if let count = rule.count, produced >= count { return false }
            if start > window.end { return false }
            produced += 1
            guard !isException(start) else { return true }
            let occurrence = DateInterval(start: start, duration: duration)
            if overlaps(occurrence, window) { results.append(occurrence) }
            return true
        }

        let interval = max(1, rule.interval)
        switch rule.frequency {
        case .daily, .monthly, .yearly:
            let component: Calendar.Component = rule.frequency == .daily ? .day : (rule.frequency == .monthly ? .month : .year)
            for step in 0..<maxIterations {
                guard let date = calendar.date(byAdding: component, value: step * interval, to: event.start) else { break }
                if !consider(date) { break }
            }

        case .weekly:
            let startWeekday = calendar.component(.weekday, from: event.start)
            let weekdays = (rule.weekdays.isEmpty ? [startWeekday] : rule.weekdays)
                .sorted { mondayIndex($0) < mondayIndex($1) }
            let weekStart = calendar.startOfWeek(for: event.start)
            var finished = false
            for week in 0..<maxIterations where !finished {
                guard let base = calendar.date(byAdding: .weekOfYear, value: week * interval, to: weekStart) else { break }
                for weekday in weekdays {
                    guard let day = calendar.date(byAdding: .day, value: mondayIndex(weekday), to: base),
                          let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
                    else { continue }
                    if date < event.start { continue }
                    if !consider(date) { finished = true; break }
                }
            }
        }
        return results
    }

    /// Monday = 0 … Sunday = 6, from a `Calendar` weekday (1 = Sunday).
    static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    private static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        if a.duration == 0 { return b.start <= a.start && a.start <= b.end }
        return a.start < b.end && b.start < a.end
    }

    // MARK: - Agenda

    /// Every dated thing in `window`, with holidays and reading week removing
    /// the class meetings they cancel.
    static func agenda(
        events: [DashEvent],
        assessments: [Assessment],
        in window: DateInterval,
        includeHidden: Bool = false
    ) -> [AgendaItem] {
        let visible = events.filter { ($0.status != .cancelled) && (includeHidden || !$0.isHidden) }

        // Days on which classes are cancelled.
        var cancelledDays: [DateInterval] = []
        for event in visible where event.cancelsClasses {
            let calendar = Waterloo.calendar
            for occurrence in occurrences(of: event, in: window) {
                let start = calendar.startOfDay(for: occurrence.start)
                let endDay = occurrence.end > occurrence.start ? occurrence.end.addingTimeInterval(-1) : occurrence.start
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay)) ?? occurrence.end
                cancelledDays.append(DateInterval(start: start, end: max(end, start)))
            }
        }

        // Timetable test slots ("CS145 - TST 201" from Quest or UW Flow) that
        // the course's own assessment already covers: the assessment carries
        // the title, coverage and mark, so the slot would only duplicate it.
        let assessmentSlots: [(code: String, interval: DateInterval)] = assessments.compactMap { assessment in
            guard assessment.kind.isSeated, let due = assessment.due, let end = assessment.agendaEnd else { return nil }
            return (assessment.courseCode, DateInterval(start: due, end: max(end, due)))
        }

        var items: [AgendaItem] = []
        for event in visible {
            for occurrence in occurrences(of: event, in: window) {
                if event.kind.isClassMeeting || event.kind == .officeHours,
                   cancelledDays.contains(where: { $0.start <= occurrence.start && occurrence.start < $0.end }) {
                    continue
                }
                if event.kind.isSeated, let code = event.courseCode,
                   assessmentSlots.contains(where: { $0.code == code && overlaps($0.interval, occurrence) }) {
                    continue
                }
                items.append(AgendaItem(
                    id: "\(event.id)@\(Int(occurrence.start.timeIntervalSince1970))",
                    origin: .event(event.id),
                    title: event.title,
                    courseCode: event.courseCode,
                    kind: event.kind,
                    start: occurrence.start,
                    end: occurrence.end,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    detail: event.notes
                ))
            }
        }

        for assessment in assessments {
            guard let due = assessment.due, let end = assessment.agendaEnd else { continue }
            let interval = DateInterval(start: due, end: max(end, due))
            guard overlaps(interval, window) else { continue }
            items.append(AgendaItem(
                id: "assessment:\(assessment.id.uuidString)",
                origin: .assessment(assessment.id),
                title: assessment.title,
                courseCode: assessment.courseCode,
                kind: assessment.kind,
                start: due,
                end: max(end, due),
                isAllDay: false,
                location: assessment.location,
                detail: assessment.coverage.map { "Covers \($0)" },
                isDone: assessment.isDone || assessment.isGraded
            ))
        }

        return items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title < rhs.title
        }
    }
}
