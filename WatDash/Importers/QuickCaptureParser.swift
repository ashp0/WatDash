//
//  QuickCaptureParser.swift
//  WatDash
//

import Foundation

/// Turns one line of plain English into a dated entry:
///
///   "CS 135 OH Tue 2-3pm MC 4065 weekly until Dec 4"
///   "math137 quiz 4 oct 19"
///   "A4 due fri 11:59pm"
///   "hack the north info session tomorrow 6pm SLC great hall"
///
/// Deterministic on purpose. The on-device model (SmartCapture) can clean up a
/// messy sentence into these fields first, but date arithmetic always happens
/// here, where it can be tested — language models are bad at "next Tuesday".
struct CaptureResult: Hashable, Sendable {
    var title: String
    var courseCode: String?
    var kind: EventKind
    var start: Date?
    var end: Date?
    var isAllDay: Bool = false
    var location: String?
    var recurrence: Recurrence?
    var assessmentNumber: String?

    /// How much of the line was understood; low scores go to the inbox.
    var confidence: Double

    var isAssessment: Bool { kind.isAssessment }
}

enum QuickCaptureParser {

    static let buildingPattern = #"\b(MC|DC|E2|E3|E5|E6|E7|EIT|STC|RCH|PHY|QNC|M3|DWE|CPH|HH|AL|EV1|EV2|EV3|SLC|PAC|OPT|EXP|B1|B2|C2|ESC|MKV|TC|NH|BMH|LHI|ML|PAS|HS|STJ|REN|CGR|UWP|REV|V1|MHR|LIB|SCH|GSC|CIF|TJB|AHS)\s?(\d{3,4}[A-Z]?)\b"#

    static func parse(_ input: String, now: Date, knownCourses: [String], calendar: Calendar = Waterloo.calendar) -> CaptureResult {
        var text = " " + input.trimmed + " "
        var understood = 0.0

        func strip(_ pattern: String) {
            text = text.replacingMatches(pattern, with: " ", options: [.caseInsensitive])
        }

        // Course.
        var course: String?
        if let code = CourseCode.find(in: text, among: knownCourses) {
            course = code
            let compact = code.replacingOccurrences(of: " ", with: "")
            let subject = code.split(separator: " ").first.map(String.init) ?? code
            let number = code.split(separator: " ").last.map(String.init) ?? ""
            strip("\\b\(subject)[ -]?\(number)\\b")
            strip("\\b\(compact)\\b")
            understood += 1
        }

        // Kind (+ assessment number: "quiz 4", "A4", "assignment 3", "midterm 2").
        var kind = EventKind.event
        var number: String?
        let lower = text.lowercased()
        let kindTable: [(String, EventKind)] = [
            (#"\b(office hours?|oh)\b"#, .officeHours),
            (#"\b(quiz)\s*#?([a-z]?\d{1,2})?\b"#, .quiz),
            (#"\b(midterm|test)\s*#?(\d{1,2})?\b"#, .test),
            (#"\b(final exam|final|exam)\b"#, .exam),
            (#"\b(assignment|assn|hw|homework|problem set|ps)\s*#?([a-z]?\d{1,2})?\b"#, .assignment),
            (#"\b(a)(\d{1,2})\b"#, .assignment),
            (#"\b(due|deadline|submit)\b"#, .deadline),
            (#"\b(tutorial|tut)\b"#, .tutorial),
            (#"\b(lecture|lec|class)\b"#, .lecture),
            (#"\b(lab)\b"#, .lab),
        ]
        for (pattern, candidate) in kindTable {
            if let match = lower.firstMatch(pattern) {
                kind = candidate
                if match.count > 2, !match[2].isEmpty { number = match[2].uppercased() }
                // A number-less "due" after an assignment keeps it an assignment.
                if candidate == .deadline, lower.firstMatch(#"\b(a\d|assignment|hw)"#) != nil { kind = .assignment }
                strip(pattern)
                understood += 1
                break
            }
        }
        if kind != .deadline { strip(#"\b(due|by)\b"#) }

        // Location.
        var location: String?
        if let building = text.uppercased().firstMatch(buildingPattern) {
            location = "\(building[1]) \(building[2])"
            strip(buildingPattern)
            understood += 0.5
        } else if let place = text.firstMatch(#"(?:\s@\s?|\sin\s)([A-Z][\w'&]+(?:\s[A-Z][\w'&]+){0,3})"#) {
            location = place[1].trimmed
            strip(NSRegularExpression.escapedPattern(for: place[0]))
        }

        // Recurrence words ("weekly", "every tue", "until Dec 4", "for 6 weeks").
        var repeatsWeekly = false
        var until: Date?
        var count: Int?
        if text.lowercased().firstMatch(#"\b(weekly|every week|each week|every (mon|tue|wed|thu|fri|sat|sun)\w*)\b"#) != nil {
            repeatsWeekly = true
            strip(#"\b(weekly|every week|each week)\b"#)
            strip(#"\bevery\b"#)
        }
        if let untilMatch = text.firstMatch(#"(?i)\buntil\s+([A-Za-z]{3,9}\.?\s+\d{1,2}|\d{1,2}/\d{1,2})"#) {
            until = date(fromDayText: untilMatch[1], now: now, calendar: calendar, preferFuture: true)
            strip(NSRegularExpression.escapedPattern(for: untilMatch[0]))
        }
        if let forMatch = text.firstMatch(#"(?i)\bfor\s+(\d{1,2})\s+weeks?\b"#) {
            count = Int(forMatch[1])
            repeatsWeekly = true
            strip(NSRegularExpression.escapedPattern(for: forMatch[0]))
        }

        // Day (explicit dates first, so "2026-12-04" isn't read as 12–4).
        var day: Date?
        var weekday: Int?
        if let explicit = text.firstMatch(#"(?i)\b((?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2})\b"#) {
            day = date(fromDayText: explicit[1], now: now, calendar: calendar, preferFuture: true)
            strip(NSRegularExpression.escapedPattern(for: explicit[0]))
            understood += 1
        } else if text.lowercased().firstMatch(#"\b(today|tonight)\b"#) != nil {
            day = calendar.startOfDay(for: now)
            strip(#"\b(today|tonight)\b"#)
            understood += 1
        } else if text.lowercased().firstMatch(#"\b(tomorrow|tmr|tmrw)\b"#) != nil {
            day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            strip(#"\b(tomorrow|tmr|tmrw)\b"#)
            understood += 1
        }
        // Time.
        var startMinutes: Int?
        var endMinutes: Int?
        if let range = text.firstMatch(#"(?i)\b(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:-|–|—|to)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\b"#),
           range[0].contains(":") || range[0].lowercased().contains("m") || (Int(range[1]) ?? 99) <= 12 && (Int(range[2]) ?? 99) <= 12 {
            let endText = range[2].lowercased()
            let hasEndMeridiem = endText.contains("m")
            var end = MeetingText.minutes(from: range[2]) ?? 0
            if !hasEndMeridiem { end = guessMeridiem(end) }
            let startHasMeridiem = range[1].lowercased().contains("m")
            var start = MeetingText.minutes(from: range[1], defaultPM: startHasMeridiem ? nil : end >= 12 * 60) ?? 0
            if start > end, !startHasMeridiem { start -= 12 * 60 }
            if start < 0 { start += 12 * 60 }
            startMinutes = start
            endMinutes = end
            strip(NSRegularExpression.escapedPattern(for: range[0]))
            understood += 1
        } else if let single = text.firstMatch(#"(?i)(?:\bat\s+|@\s*)?\b(\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2}|noon|midnight)\b"#) {
            let token = single[1].lowercased()
            if token == "noon" { startMinutes = 12 * 60 }
            else if token == "midnight" { startMinutes = 23 * 60 + 59 }
            else if var minutes = MeetingText.minutes(from: single[1]) {
                if !token.contains("m") { minutes = guessMeridiem(minutes) }
                startMinutes = minutes
            }
            strip(NSRegularExpression.escapedPattern(for: single[0]))
            understood += 1
        }

        // Weekday names, after the time so "today" can be skipped once it has passed.
        if let named = text.lowercased().firstMatch(#"\b(next\s+)?(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:day|nesday|sday|urday|rsday)?s?\b"#) {
            let map = ["sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7]
            weekday = map[named[2]]
            if day == nil, let weekday {
                day = nextDate(weekday: weekday, after: now, skipWeek: !named[1].isEmpty, minutes: startMinutes, calendar: calendar)
                understood += 1
            }
            strip(NSRegularExpression.escapedPattern(for: named[0]))
        }

        // Assemble dates.
        var start: Date?
        var end: Date?
        var isAllDay = false
        if let day {
            if let startMinutes {
                start = calendar.date(byAdding: .minute, value: startMinutes, to: calendar.startOfDay(for: day))
                if let endMinutes {
                    end = calendar.date(byAdding: .minute, value: endMinutes, to: calendar.startOfDay(for: day))
                } else if kind.isDue {
                    end = start
                } else {
                    end = start.map { $0.addingTimeInterval(defaultDuration(for: kind)) }
                }
            } else if kind.isDue {
                start = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day)
                end = start
            } else {
                start = calendar.startOfDay(for: day)
                end = calendar.date(byAdding: .day, value: 1, to: start!)
                isAllDay = true
            }
        } else if let startMinutes {
            // A time with no day: the next time that clock time comes round.
            var candidate = calendar.date(byAdding: .minute, value: startMinutes, to: calendar.startOfDay(for: now))!
            if candidate < now { candidate = calendar.date(byAdding: .day, value: 1, to: candidate)! }
            start = candidate
            end = endMinutes.flatMap { calendar.date(byAdding: .minute, value: $0 - startMinutes, to: candidate) }
                ?? candidate.addingTimeInterval(kind.isDue ? 0 : defaultDuration(for: kind))
        }

        var recurrence: Recurrence?
        if repeatsWeekly, let start {
            let startWeekday = weekday ?? calendar.component(.weekday, from: start)
            recurrence = Recurrence(frequency: .weekly, interval: 1, count: count,
                                    until: until.flatMap { calendar.date(bySettingHour: 23, minute: 59, second: 0, of: $0) },
                                    weekdays: [startWeekday])
        }

        // Title: whatever words are left, or a sensible default.
        let leftover = text
            .replacingMatches(#"\s+[-–,:;]+\s+"#, with: " ")
            .replacingMatches(#"(?i)\b(on|at|from|in|the)\s*$"#, with: "")
            .replacingMatches(#"(?i)^\s*(on|at|from)\b"#, with: "")
            .collapsingWhitespace
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–,.:;"))
        let title: String
        switch kind {
        case .officeHours:
            title = [course, "office hours"].compactMap { $0 }.joined(separator: " ") + (leftover.isEmpty ? "" : " — \(leftover)")
        case .quiz, .test, .exam, .assignment:
            let base: String
            switch kind {
            case .quiz: base = "Quiz"
            case .test: base = "Midterm"
            case .exam: base = "Final exam"
            default: base = "Assignment"
            }
            let numbered = number.map { "\(base) \($0.replacingOccurrences(of: "A", with: ""))" } ?? base
            title = leftover.isEmpty ? numbered : "\(numbered) — \(leftover)"
        default:
            let pieces = [course, leftover.nilIfEmpty ?? kind.label]
            title = pieces.compactMap { $0 }.joined(separator: " ")
        }

        let confidence = min(1, understood / 3.5)
        return CaptureResult(title: title.trimmed.isEmpty ? input.trimmed : title.trimmed,
                             courseCode: course, kind: kind, start: start, end: end, isAllDay: isAllDay,
                             location: location, recurrence: recurrence, assessmentNumber: number,
                             confidence: start == nil ? min(confidence, 0.3) : confidence)
    }

    /// 1–7 without am/pm means afternoon on a student timetable; 8–11 morning.
    private static func guessMeridiem(_ minutes: Int) -> Int {
        let hour = minutes / 60
        return (1...7).contains(hour) ? minutes + 12 * 60 : minutes
    }

    private static func defaultDuration(for kind: EventKind) -> TimeInterval {
        switch kind {
        case .quiz: 50 * 60
        case .test: 110 * 60
        case .exam: 150 * 60
        case .lecture: 50 * 60
        case .tutorial, .lab: 80 * 60
        default: 60 * 60
        }
    }

    static func nextDate(weekday: Int, after now: Date, skipWeek: Bool, minutes: Int?, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard calendar.component(.weekday, from: day) == weekday else { continue }
            if offset == 0 {
                // Today only counts if the time hasn't passed.
                guard let minutes, let at = calendar.date(byAdding: .minute, value: minutes, to: day), at > now else { continue }
            }
            if skipWeek && offset < 7 { continue }
            return day
        }
        return nil
    }

    /// "Dec 4", "December 4th", "12/4", "2026-12-04".
    static func date(fromDayText raw: String, now: Date, calendar: Calendar, preferFuture: Bool) -> Date? {
        let year = calendar.component(.year, from: now)
        var candidate: Date?
        if let iso = raw.firstMatch(#"(\d{4})-(\d{2})-(\d{2})"#) {
            return calendar.date(from: DateComponents(year: Int(iso[1]), month: Int(iso[2]), day: Int(iso[3])))
        } else if let slash = raw.firstMatch(#"(\d{1,2})/(\d{1,2})"#) {
            candidate = calendar.date(from: DateComponents(year: year, month: Int(slash[1]), day: Int(slash[2])))
        } else if let md = raw.firstMatch(#"([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})"#) {
            candidate = OutlineParser.monthDay(md[1], md[2], year: year, calendar: calendar)
        }
        guard let date = candidate else { return nil }
        // "Jan 12" typed in November means next January.
        if preferFuture, date < calendar.date(byAdding: .month, value: -2, to: now)! {
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
        return date
    }
}
