//
//  ICSImport.swift
//  WatDash
//

import Foundation

/// Maps parsed iCalendar events onto store events, recognising UW class
/// titles ("CS 135 LEC 002") so imported timetables get course colours and
/// the right kind without any tagging.
enum ICSImport {
    static func events(from parsed: [ICSParser.ParsedEvent], sourceID: UUID?, knownCourses: [String]) -> [DashEvent] {
        parsed.map { item in
            let text = "\(item.summary) \(item.notes ?? "")"
            let course = CourseCode.find(in: item.summary, among: knownCourses)
            let kind = classify(summary: item.summary, notes: item.notes, isAllDay: item.isAllDay, hasCourse: course != nil)
            var recurrence: Recurrence?
            if let rule = item.recurrence {
                recurrence = Recurrence(
                    frequency: Recurrence.Frequency(rawValue: rule.frequency.rawValue) ?? .weekly,
                    interval: rule.interval, count: rule.count, until: rule.until, weekdays: rule.weekdays
                )
            }
            let lower = text.lowercased()
            let cancels = kind == .holiday && (lower.contains("reading week") || lower.contains("holiday")
                || lower.contains("no classes") || lower.contains("thanksgiving") || lower.contains("family day")
                || lower.contains("victoria day") || lower.contains("canada day") || lower.contains("civic holiday")
                || lower.contains("labour day") || lower.contains("good friday") || lower.contains("study day"))
            return DashEvent(
                id: "\(sourceID?.uuidString ?? "ics"):\(item.uid)",
                title: item.summary,
                courseCode: course,
                kind: kind,
                start: item.start,
                end: item.end,
                isAllDay: item.isAllDay,
                location: item.location,
                notes: item.notes,
                url: item.url,
                recurrence: recurrence,
                exceptionDates: item.exceptionDates,
                timeZoneID: item.timeZone?.identifier,
                sourceID: sourceID,
                status: item.isCancelled ? .cancelled : .confirmed,
                cancelsClasses: cancels
            )
        }
    }

    static func classify(summary: String, notes: String?, isAllDay: Bool, hasCourse: Bool) -> EventKind {
        let upper = summary.uppercased()
        if let component = upper.firstMatch(#"\b(LEC|TUT|LAB|SEM|TST)\b"#), let kind = EventKind.fromComponent(component[1]) {
            return kind
        }
        let lower = summary.lowercased()
        if lower.contains("office hour") || lower.firstMatch(#"\boh\b"#) != nil { return .officeHours }
        if lower.contains("quiz") { return .quiz }
        if lower.contains("midterm") { return .test }
        if lower.contains("final exam") || (hasCourse && lower.contains("exam")) { return .exam }
        if lower.contains("assignment") || lower.contains(" due") || lower.hasPrefix("due") { return .assignment }
        if lower.contains("lecture") { return .lecture }
        if lower.contains("tutorial") { return .tutorial }
        if isAllDay, ["reading week", "holiday", "no classes", "thanksgiving", "family day", "day off", "study day", "good friday", "labour day", "victoria day", "canada day", "civic holiday", "christmas", "new year"].contains(where: lower.contains) {
            return .holiday
        }
        return hasCourse ? .lecture : .event
    }
}
