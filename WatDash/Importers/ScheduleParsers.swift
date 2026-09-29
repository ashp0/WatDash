//
//  ScheduleParsers.swift
//  WatDash
//

import Foundation

/// A class meeting pattern parsed from Quest or a course outline:
/// "MATH 137 LEC 005, MWF 10:30–11:20, STC 0010, Sep 9 – Dec 8".
struct ParsedMeeting: Hashable, Sendable, Identifiable {
    var id: String { "\(courseCode) \(component ?? "") \(section ?? "") \(weekdays) \(startMinutes)" }
    var courseCode: String
    var courseTitle: String?
    var component: String?     // LEC / TUT / LAB / TST
    var section: String?       // "005"
    var weekdays: [Int]        // Calendar weekdays (1 = Sunday)
    var startMinutes: Int      // minutes after midnight
    var endMinutes: Int
    var location: String?
    var instructor: String?
    var firstDay: Date?        // start of the date range (Waterloo midnight)
    var lastDay: Date?

    var label: String {
        [component, section].compactMap { $0 }.joined(separator: " ")
    }

    /// Materialize as a recurring store event.
    func event(sourceID: UUID?, fallbackStart: Date, fallbackEnd: Date) -> DashEvent? {
        let calendar = Waterloo.calendar
        let rangeStart = firstDay ?? fallbackStart
        let rangeEnd = lastDay ?? fallbackEnd
        // First meeting on or after the range start that falls on a meeting day.
        var day = calendar.startOfDay(for: rangeStart)
        var guardCount = 0
        while !weekdays.contains(calendar.component(.weekday, from: day)) && guardCount < 8 {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guardCount += 1
        }
        guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: day),
              let end = calendar.date(byAdding: .minute, value: endMinutes, to: day) else { return nil }
        let until = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: rangeEnd)
        let kind = EventKind.fromComponent(component) ?? .lecture
        let isSingle = firstDay != nil && lastDay != nil && calendar.isDate(firstDay!, inSameDayAs: lastDay!)
        return DashEvent(
            id: "\(sourceID?.uuidString ?? "manual"):\(courseCode):\(label):\(weekdays.map(String.init).joined()):\(startMinutes)",
            title: "\(courseCode) \(label)".trimmed,
            courseCode: courseCode,
            kind: kind,
            start: start,
            end: end,
            location: location,
            notes: instructor.map { "Instructor: \($0)" },
            recurrence: isSingle ? nil : .weekly(on: weekdays, until: until),
            timeZoneID: Waterloo.timeZone.identifier,
            sourceID: sourceID
        )
    }
}

enum MeetingText {
    /// "MWF", "TTh", "MTWThF", "Mon, Wed, Fri", "Mondays" → Calendar weekdays.
    static func weekdays(from raw: String) -> [Int] {
        let text = raw.trimmed
        // Long names first ("Monday, Wednesday", "Mondays").
        let long: [(String, Int)] = [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
        let lower = text.lowercased()
        if lower.contains("day") || lower.contains(",") || lower.count > 7 && lower.contains(" ") {
            let found = long.filter { lower.contains($0.0) }.map(\.1)
            if !found.isEmpty { return found }
        }
        // Quest compact codes. Two-letter tokens first so "Th" isn't read as T+h.
        var result: [Int] = []
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("Th") || rest.hasPrefix("TH") || rest.hasPrefix("R") {
                result.append(5); index = text.index(index, offsetBy: rest.hasPrefix("R") ? 1 : 2)
            } else if rest.hasPrefix("Su") || rest.hasPrefix("SU") || rest.hasPrefix("U") {
                result.append(1); index = text.index(index, offsetBy: rest.hasPrefix("U") ? 1 : 2)
            } else if rest.hasPrefix("Sa") || rest.hasPrefix("SA") || rest.hasPrefix("S") {
                result.append(7); index = text.index(index, offsetBy: (rest.hasPrefix("Sa") || rest.hasPrefix("SA")) ? 2 : 1)
            } else if rest.hasPrefix("Tu") || rest.hasPrefix("TU") {
                result.append(3); index = text.index(index, offsetBy: 2)
            } else {
                switch rest.first {
                case "M": result.append(2)
                case "T": result.append(3)
                case "W": result.append(4)
                case "F": result.append(6)
                default: break
                }
                index = text.index(after: index)
            }
        }
        var seen = Set<Int>()
        return result.filter { seen.insert($0).inserted }
    }

    /// "10:30AM", "1:30 PM", "13:30" → minutes after midnight.
    static func minutes(from raw: String, defaultPM: Bool? = nil) -> Int? {
        guard let groups = raw.trimmed.firstMatch(#"^(\d{1,2})(?::(\d{2}))?\s*([AaPp]\.?[Mm]\.?)?$"#) else { return nil }
        guard var hour = Int(groups[1]) else { return nil }
        let minute = Int(groups[2]) ?? 0
        let meridiem = groups[3].lowercased().replacingOccurrences(of: ".", with: "")
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        if meridiem.isEmpty, let defaultPM, defaultPM, hour < 12 { hour += 12 }
        guard hour < 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }

    /// "10:30AM - 11:20AM" / "05:30PM - 06:50PM" / "4:00–5:20 PM".
    static func timeRange(from raw: String) -> (Int, Int)? {
        let pattern = #"(\d{1,2}(?::\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?)\s*(?:-|–|—|to)\s*(\d{1,2}(?::\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?)"#
        guard let groups = raw.firstMatch(pattern) else { return nil }
        // "20 - 35" is a range of numbers, not of times: require a colon or a
        // meridiem somewhere before trusting it.
        let whole = groups[0].lowercased()
        guard whole.contains(":") || whole.contains("m") else { return nil }
        let endIsPM = groups[2].lowercased().contains("p")
        let startHasMeridiem = groups[1].lowercased().contains("m")
        guard let end = minutes(from: groups[2]) else { return nil }
        // "4:00–5:20 PM": the start borrows the end's meridiem when it has none.
        var start = minutes(from: groups[1], defaultPM: startHasMeridiem ? nil : endIsPM)
        if let s = start, s > end, !startHasMeridiem { start = s - 12 * 60 }
        guard let start else { return nil }
        return (start, end)
    }
}

// MARK: - Quest "My Class Schedule" (List View) paste

/// Parses the text you get by selecting all of Quest → Enroll → My Class
/// Schedule → List View and copying. Tabs usually survive the copy; when they
/// don't, the row is recovered from its shape.
enum QuestScheduleParser {
    static func parse(_ text: String, year: Int) -> [ParsedMeeting] {
        var meetings: [ParsedMeeting] = []
        var currentCode: String?
        var currentTitle: String?
        var lastComponent: String?
        var lastSection: String?

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Waterloo.timeZone
        formatter.dateFormat = "MM/dd/yyyy"

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Course header: "MATH 137 - Calculus 1 for Honours Mathematics"
            if let header = line.firstMatch(#"^([A-Z]{2,6})\s?(\d{3}[A-Z]?)\s+-\s+(.+)$"#) {
                currentCode = "\(header[1]) \(header[2])"
                currentTitle = header[3].trimmed
                lastComponent = nil
                lastSection = nil
                continue
            }

            guard let code = currentCode,
                  let days = line.firstMatch(#"(?:^|\s|\t)((?:Mo|Tu|We|Th|Fr|Sa|Su|M|T|W|R|F|S|U)+)\s+(\d{1,2}:\d{2}\s?[AP]M)\s*-\s*(\d{1,2}:\d{2}\s?[AP]M)"#),
                  let start = MeetingText.minutes(from: days[2]),
                  let end = MeetingText.minutes(from: days[3])
            else { continue }

            let cells = line.components(separatedBy: "\t").map(\.trimmed)
            var component = line.firstMatch(#"\b(LEC|TUT|LAB|TST|SEM|PRJ)\b"#)?[1]
            var section = line.firstMatch(#"\b(\d{3})\b\s+(?:LEC|TUT|LAB|TST|SEM|PRJ)\b"#)?[1]
            if component == nil { component = lastComponent }
            if section == nil { section = lastSection }
            lastComponent = component
            lastSection = section

            // Room: the cell after the time, or a building-room token.
            var room: String?
            var instructor: String?
            if let timeIndex = cells.firstIndex(where: { $0.contains(days[2]) }), cells.count > timeIndex + 1 {
                room = cells[timeIndex + 1].nilIfEmpty
                if cells.count > timeIndex + 2 { instructor = cells[timeIndex + 2].nilIfEmpty }
            } else {
                room = line.firstMatch(#"\b([A-Z]{1,4}\d?\s\d{3,4}[A-Z]?)\b"#)?[1]
            }
            if room == "TBA" { room = nil }
            if instructor == "TBA" || instructor == "Staff" { instructor = nil }

            var first: Date?
            var last: Date?
            if let range = line.firstMatch(#"(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})"#) {
                first = formatter.date(from: range[1])
                last = formatter.date(from: range[2])
            }

            meetings.append(ParsedMeeting(
                courseCode: code, courseTitle: currentTitle, component: component, section: section,
                weekdays: MeetingText.weekdays(from: days[1]), startMinutes: start, endMinutes: end,
                location: room, instructor: instructor, firstDay: first, lastDay: last
            ))
        }
        return meetings
    }
}

// MARK: - outline.uwaterloo.ca saved page

/// Everything useful in a course outline saved from outline.uwaterloo.ca:
/// every section's meeting pattern and the assessment table.
struct ParsedOutline: Sendable {
    struct AssessmentRow: Hashable, Sendable {
        var component: String
        var dateText: String
        var location: String
        var weight: Double?
    }

    var courseCode: String?
    var courseTitle: String?
    var termName: String?
    var meetings: [ParsedMeeting]
    var assessments: [AssessmentRow]

    var sectionLabels: [String] { Array(Set(meetings.map(\.label))).sorted() }
}

enum OutlineParser {
    static func parse(html: String, year: Int) -> ParsedOutline {
        let calendar = Waterloo.calendar

        func text(_ fragment: String) -> String {
            fragment
                .replacingMatches(#"<[^>]+>"#, with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .collapsingWhitespace
        }

        // Title block: "<h1 ...>MATH 137</h1>" varies; the <title> is reliable:
        // "Fall 2026: Calculus 1 for Honours Mathematics".
        var termName: String?
        var courseTitle: String?
        if let title = html.firstMatch(#"<title>\s*([^<:]+):\s*([^<]+)</title>"#, options: [.caseInsensitive]) {
            termName = text(title[1]).nilIfEmpty
            courseTitle = text(title[2]).nilIfEmpty
        }

        // Class schedule table rows.
        var meetings: [ParsedMeeting] = []
        var courseCode: String?
        if let schedule = html.firstMatch(#"(?s)<figure class="schedule-info">(.*?)</figure>"#) {
            for row in schedule[1].allMatches(#"(?s)<tr>(.*?)</tr>"#) {
                let body = row[1]
                guard let head = body.firstMatch(#"(?s)<th[^>]*>(.*?)</th>"#) else { continue }
                let headText = text(head[1])
                guard let parts = headText.firstMatch(#"([A-Z]{2,6})\s?(\d{3}[A-Z]?)\s+(\d{3})\s+\[([A-Z]{3})\]"#) else { continue }
                let code = "\(parts[1]) \(parts[2])"
                courseCode = courseCode ?? code

                let cells = body.allMatches(#"(?s)<td[^>]*>(.*?)</td>"#).map { $0[1] }
                guard cells.count >= 3 else { continue }
                let daysVisual = cells[0].firstMatch(#"(?s)title="([^"]+)""#)?[1] ?? text(cells[0])
                let weekdays = MeetingText.weekdays(from: daysVisual)
                guard !weekdays.isEmpty, let times = MeetingText.timeRange(from: text(cells[1])) else { continue }

                var first: Date?
                var last: Date?
                if let range = text(cells[0]).firstMatch(#"([A-Z][a-z]{2})\s+(\d{1,2})\s*-\s*([A-Z][a-z]{2})\s+(\d{1,2})"#) {
                    first = monthDay(range[1], range[2], year: year, calendar: calendar)
                    last = monthDay(range[3], range[4], year: year, calendar: calendar)
                } else if let single = text(cells[0]).firstMatch(#"\b([A-Z][a-z]{2})\s+(\d{1,2})\b"#) {
                    first = monthDay(single[1], single[2], year: year, calendar: calendar)
                    last = first
                }
                let instructor = cells.count > 3 ? cells[3].firstMatch(#"<span>([^<]+)</span>"#)?[1].trimmed : nil

                meetings.append(ParsedMeeting(
                    courseCode: code, courseTitle: courseTitle, component: parts[4], section: parts[3],
                    weekdays: weekdays, startMinutes: times.0, endMinutes: times.1,
                    location: text(cells[2]).nilIfEmpty, instructor: instructor,
                    firstDay: first, lastDay: last
                ))
            }
        }

        // Assessments & Activities table.
        var assessments: [ParsedOutline.AssessmentRow] = []
        if let section = html.firstMatch(#"(?s)id="assessments_amp_activities".*?<table class="multitable">(.*?)</table>"#) {
            for row in section[1].allMatches(#"(?s)<tr>(.*?)</tr>"#) {
                let cells = row[1].allMatches(#"(?s)<td[^>]*>(.*?)</td>"#).map { text($0[1]) }
                guard cells.count >= 2 else { continue }
                let weight = cells.last.flatMap { Double($0.replacingOccurrences(of: "%", with: "").trimmed) }
                assessments.append(.init(component: cells[0], dateText: cells.count > 2 ? cells[1] : "",
                                         location: cells.count > 3 ? cells[2] : "", weight: weight))
            }
        }

        return ParsedOutline(courseCode: courseCode, courseTitle: courseTitle, termName: termName,
                             meetings: meetings, assessments: assessments)
    }

    static func monthDay(_ month: String, _ day: String, year: Int, calendar: Calendar) -> Date? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let index = months.firstIndex(of: String(month.lowercased().prefix(3))), let dayNumber = Int(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: index + 1, day: dayNumber))
    }

    /// Turns the outline's assessment rows into a grading scheme.
    static func scheme(from rows: [ParsedOutline.AssessmentRow]) -> GradeScheme {
        var scheme = GradeScheme()
        for row in rows {
            guard let weight = row.weight, weight > 0 else { continue }
            let lower = row.component.lowercased()
            let isExam = lower.contains("exam") || lower.contains("midterm") || lower.contains("test")
            var component = GradeComponent(name: row.component, weight: weight, isExam: isExam)
            if lower.contains("quiz") || lower.contains("assignment") { component.expectedCount = nil }
            else { component.expectedCount = 1 }
            scheme.components.append(component)
        }
        return scheme
    }
}
