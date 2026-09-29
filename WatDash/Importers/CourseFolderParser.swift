//
//  CourseFolderParser.swift
//  WatDash
//

import Foundation

/// Reads a course folder's CLAUDE.md — the file that already holds the term
/// calendar, the grading scheme, the notes page map and the study pages — and
/// turns it into structured data. No retyping: the same file that briefs Claude
/// fills the dashboard.
struct ParsedCourseFolder: Sendable {
    struct Row: Hashable, Sendable {
        var title: String
        var kind: EventKind
        var due: Date?
        var end: Date?
        var coverage: String?
        var rawDate: String
        /// "15/19" or "91.67%" from a Mark column: marks already posted on
        /// LEARN, Crowdmark or the course's marks page.
        var score: Double?
        var outOf: Double?
        /// Room and seat from a Room column ("MC 1085, seat E-14").
        var location: String?
    }

    struct NoClassRange: Hashable, Sendable {
        var label: String
        var start: Date
        var end: Date   // inclusive last day
    }

    var code: String?
    var title: String?
    var termName: String?
    var year: Int?
    var isSelfStudy = false
    var rows: [Row] = []
    var components: [GradeComponent] = []
    var noClassRanges: [NoClassRange] = []
    var studyLinks: [StudyLink] = []
    var pageMap: [NotesSection] = []
    var notesFile: String?
    /// "## Office hours" bullets, each a quick-capture line such as
    /// "Tue 11:30am–12:30pm MC 5473, Troy Vasiga, weekly until Dec 8".
    var officeHours: [String] = []
    var teachDontAnswer = false
    /// Palette index from the study page's accent ("blue accent"), so the app
    /// uses the same colour as the course's study pages.
    var accentIndex: Int?
}

enum CourseFolderParser {

    static func parse(markdown: String, fallbackYear: Int) -> ParsedCourseFolder {
        var result = ParsedCourseFolder()
        let lines = markdown.components(separatedBy: .newlines)

        // "# MATH 137: Calculus 1 for Honours Mathematics (Fall 2026)"
        if let heading = lines.first(where: { $0.hasPrefix("# ") }) {
            let body = String(heading.dropFirst(2))
            result.code = CourseCode.normalize(body)
            result.isSelfStudy = body.lowercased().contains("self-study")
            if let term = body.firstMatch(#"\((Fall|Winter|Spring)\s+(\d{4})\)"#) {
                result.termName = "\(term[1]) \(term[2])"
                result.year = Int(term[2])
            }
            if let title = body.firstMatch(#"^[A-Z]{2,6}\s?\d{3}[A-Z]?:\s*(.+?)(?:\s*\((?:Fall|Winter|Spring)\s+\d{4}\))?$"#) {
                result.title = title[1].trimmed
            }
        }
        let year = result.year ?? fallbackYear

        let sections = splitSections(lines)
        let lowerAll = markdown.lowercased()
        result.teachDontAnswer = lowerAll.contains("differ from the assignment")
            || lowerAll.contains("never hand over assignment answers")
            || lowerAll.contains("solve every assignment question")

        // Grading scheme bullets and default times from "## Assessments…".
        var defaultTimes: [EventKind: (Int, Int?)] = [:]
        for (heading, body) in sections where heading.lowercased().hasPrefix("assessments") {
            for line in body {
                let clean = line.replacingOccurrences(of: "**", with: "")
                if let bullet = clean.firstMatch(#"^\s*[-*]\s+([A-Za-z][A-Za-z0-9 /]+?),\s*(\d+(?:\.\d+)?)%(?:,\s*best\s+(\d+)\s+of\s+(\d+))?"#) {
                    let name = bullet[1].trimmed
                    let lower = name.lowercased()
                    var component = GradeComponent(
                        name: name,
                        weight: Double(bullet[2]) ?? 0,
                        isExam: lower.contains("midterm") || lower.contains("final") || lower.contains("exam") || lower.contains("test")
                    )
                    if let kept = Int(bullet[3]), let total = Int(bullet[4]) {
                        component.dropLowest = max(0, total - kept)
                        component.expectedCount = total
                    } else if component.isExam {
                        component.expectedCount = 1
                    }
                    result.components.append(component)
                }
                for sentence in clean.components(separatedBy: CharacterSet(charactersIn: ".;")) {
                    let lower = sentence.lowercased()
                    let kind: EventKind? = lower.contains("quiz") ? .quiz : (lower.contains("assignment") ? .assignment : nil)
                    guard let kind, defaultTimes[kind] == nil else { continue }
                    if let range = MeetingText.timeRange(from: sentence) {
                        defaultTimes[kind] = (range.0, range.1)
                    } else if let single = sentence.firstMatch(#"(\d{1,2}:\d{2}\s*[AaPp][Mm])"#), let minutes = MeetingText.minutes(from: single[1]) {
                        let duration = sentence.firstMatch(#"(\d{2,3})\s+minutes"#).flatMap { Int($0[1]) }
                        defaultTimes[kind] = (minutes, duration.map { minutes + $0 })
                    }
                }
            }
        }
        // Also catch "Assignments are due Wednesdays at 4:05 PM." outside bullets.
        for sentence in markdown.components(separatedBy: CharacterSet(charactersIn: ".\n")) {
            let lower = sentence.lowercased()
            let kind: EventKind? = lower.hasPrefix("assignments are due") ? .assignment : (lower.hasPrefix("quizzes are") ? .quiz : nil)
            guard let kind, defaultTimes[kind] == nil else { continue }
            if let range = MeetingText.timeRange(from: sentence) {
                defaultTimes[kind] = (range.0, range.1)
            } else if let single = sentence.firstMatch(#"(\d{1,2}:\d{2}\s*[AaPp][Mm])"#), let minutes = MeetingText.minutes(from: single[1]) {
                defaultTimes[kind] = (minutes, nil)
            }
        }

        // Tables anywhere in the file.
        for table in markdownTables(lines) {
            let header = table.header.map { $0.lowercased() }
            if let titleColumn = header.firstIndex(where: { $0.contains("assessment") }),
               let dateColumn = header.firstIndex(where: { $0 == "date" || $0.contains("date") }) {
                let coverageColumn = header.lastIndex(where: { $0.contains("section") || $0.contains("covers") || $0.contains("topics") })
                let markColumn = header.firstIndex(where: { $0.contains("mark") || $0.contains("score") || $0 == "grade" })
                let roomColumn = header.firstIndex(where: { $0.contains("room") || $0.contains("seat") || $0 == "location" || $0 == "where" })
                func cell(_ column: Int?, _ row: [String]) -> String? {
                    column.flatMap { $0 < row.count ? row[$0].trimmed.nilIfEmpty : nil }
                }
                for row in table.rows where row.count > max(titleColumn, dateColumn) {
                    let title = row[titleColumn].replacingOccurrences(of: "**", with: "").trimmed
                    guard !title.isEmpty else { continue }
                    let kind = assessmentKind(for: title)
                    let rawDate = row[dateColumn].trimmed
                    let (due, end) = parseDate(rawDate, year: year, defaultTime: defaultTimes[kind])
                    let mark = cell(markColumn, row).flatMap(parseMark)
                    let room = cell(roomColumn, row).flatMap { $0 == "TBA" || $0 == "—" ? nil : $0 }
                    result.rows.append(.init(title: title, kind: kind, due: due, end: end, coverage: cell(coverageColumn, row),
                                             rawDate: rawDate, score: mark?.score, outOf: mark?.outOf, location: room))
                }
            } else if header.first.map({ $0 == "§" || $0.contains("chapter") || $0.contains("section") }) == true,
                      header.contains(where: { $0.contains("page") }) {
                result.pageMap += pageMap(from: table)
            }
        }

        // "Reading week is Oct 10–18."
        for match in markdown.allMatches(#"(?i)reading week is ([A-Z][a-z]{2})\w*\s+(\d{1,2})\s*[–-]\s*(?:([A-Z][a-z]{2})\w*\s+)?(\d{1,2})"#) {
            let calendar = Waterloo.calendar
            if let start = OutlineParser.monthDay(match[1], match[2], year: year, calendar: calendar),
               let end = OutlineParser.monthDay(match[3].isEmpty ? match[1] : match[3], match[4], year: year, calendar: calendar) {
                if !result.noClassRanges.contains(where: { $0.start == start }) {
                    result.noClassRanges.append(.init(label: "Reading week", start: start, end: end))
                }
            }
        }

        // Study pages: "- **MATH 137 Quiz Prep**: https://…"
        for (heading, body) in sections where heading.lowercased().contains("study page") {
            for line in body {
                guard let link = line.firstMatch(#"\*\*(.+?)\*\*:?\s*(https?://\S+?)[.,;)]?(?:\s|$)"#) else { continue }
                result.studyLinks.append(StudyLink(title: link[1], url: link[2]))
            }
        }

        // Office hours: "- Tue 11:30am–12:30pm MC 5473, Troy Vasiga, weekly until Dec 8"
        for (heading, body) in sections where heading.lowercased().contains("office hour") {
            for line in body {
                guard let bullet = line.firstMatch(#"^\s*[-*]\s+(.+)$"#) else { continue }
                result.officeHours.append(bullet[1].replacingOccurrences(of: "**", with: "").trimmed)
            }
        }

        // "…blue accent…" / "magenta accent" → the matching palette colour.
        if let accent = markdown.lowercased().firstMatch(#"\b(blue|magenta|pink|teal|green|orange|violet|purple|red|sky|olive|brown|slate|gray|grey)\s+accent"#) {
            let map = ["blue": 0, "magenta": 1, "pink": 1, "teal": 2, "green": 2, "orange": 3, "violet": 4, "purple": 4,
                       "red": 5, "sky": 6, "olive": 7, "brown": 8, "slate": 9, "gray": 9, "grey": 9]
            result.accentIndex = map[accent[1]]
        }

        // Notes PDF: "- `MATH_137.pdf`: course notes…"
        for (heading, body) in sections where heading.lowercased() == "files" {
            for line in body {
                if let file = line.firstMatch(#"`([^`]+\.pdf)`:?\s*(.*)"#), file[2].lowercased().contains("course notes") {
                    result.notesFile = file[1]
                }
            }
        }
        return result
    }

    /// "15/19", "15 / 19 (78.9%)", "91.67%", "100" → score and denominator.
    static func parseMark(_ raw: String) -> (score: Double, outOf: Double)? {
        if let fraction = raw.firstMatch(#"(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)"#),
           let score = Double(fraction[1]), let outOf = Double(fraction[2]), outOf > 0 {
            return (score, outOf)
        }
        if let percent = raw.firstMatch(#"^\s*(\d+(?:\.\d+)?)\s*%?\s*$"#), let score = Double(percent[1]) {
            return (score, 100)
        }
        return nil
    }

    /// Weekly office-hour events from the "## Office hours" lines, read with
    /// the quick-capture grammar. Dates resolve from `termStart`, not the
    /// clock, so every import produces the same events and the same ids.
    static func officeHourEvents(_ lines: [String], code: String, termStart: Date, sourceID: UUID?) -> [DashEvent] {
        lines.compactMap { line in
            let capture = QuickCaptureParser.parse("\(code) OH \(line)", now: termStart, knownCourses: [code])
            guard capture.kind == .officeHours, let start = capture.start, let end = capture.end else { return nil }
            return DashEvent(
                id: "officehours:\(DeterministicID.digest("\(code)|\(line)"))",
                title: capture.title, courseCode: code, kind: .officeHours,
                start: start, end: end, location: capture.location, recurrence: capture.recurrence,
                timeZoneID: Waterloo.timeZone.identifier, sourceID: sourceID
            )
        }
    }

    static func assessmentKind(for title: String) -> EventKind {
        let lower = title.lowercased()
        if lower.contains("quiz") { return .quiz }
        if lower.contains("midterm") || lower.contains("test") { return .test }
        if lower.contains("final") || lower.contains("exam") { return .exam }
        if lower.contains("assignment") || lower.contains("homework") || lower.firstMatch(#"^a\d+\b"#) != nil { return .assignment }
        if lower.contains("project") || lower.contains("report") { return .assignment }
        return .deadline
    }

    /// "Mon Sep 21", "Mon Oct 26, 7:00 PM", "Wed Oct 7, 4:00–5:20 PM", "TBA".
    static func parseDate(_ raw: String, year: Int, defaultTime: (Int, Int?)?) -> (Date?, Date?) {
        let calendar = Waterloo.calendar
        guard let md = raw.firstMatch(#"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b"#),
              let day = OutlineParser.monthDay(md[1], md[2], year: year, calendar: calendar) else { return (nil, nil) }

        var start: Int?
        var end: Int?
        let afterDate = raw.components(separatedBy: md[0]).dropFirst().joined()
        if let range = MeetingText.timeRange(from: afterDate) {
            start = range.0
            end = range.1
        } else if let single = afterDate.firstMatch(#"(\d{1,2}:\d{2}\s*[AaPp][Mm])"#) {
            start = MeetingText.minutes(from: single[1])
        } else if let defaultTime {
            start = defaultTime.0
            end = defaultTime.1
        }
        guard let start else {
            // All-day-ish: due end of day.
            return (calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day), nil)
        }
        let due = calendar.date(byAdding: .minute, value: start, to: day)
        let finish = end.flatMap { calendar.date(byAdding: .minute, value: $0, to: day) }
        return (due, finish)
    }

    // MARK: - Markdown plumbing

    private static func splitSections(_ lines: [String]) -> [(String, [String])] {
        var result: [(String, [String])] = []
        var heading = ""
        var body: [String] = []
        for line in lines {
            if line.hasPrefix("## ") {
                result.append((heading, body))
                heading = String(line.dropFirst(3)).trimmed
                body = []
            } else {
                body.append(line)
            }
        }
        result.append((heading, body))
        return result
    }

    struct Table { var header: [String]; var rows: [[String]] }

    static func markdownTables(_ lines: [String]) -> [Table] {
        var tables: [Table] = []
        var index = 0
        func cells(_ line: String) -> [String] {
            var trimmed = line.trimmed
            if trimmed.hasPrefix("|") { trimmed.removeFirst() }
            if trimmed.hasSuffix("|") { trimmed.removeLast() }
            return trimmed.components(separatedBy: "|").map(\.trimmed)
        }
        while index < lines.count {
            let line = lines[index].trimmed
            if line.hasPrefix("|"), index + 1 < lines.count,
               lines[index + 1].trimmed.hasPrefix("|"), lines[index + 1].contains("---") {
                let header = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].trimmed.hasPrefix("|") {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                tables.append(Table(header: header, rows: rows))
            } else {
                index += 1
            }
        }
        return tables
    }

    /// Two shapes in the wild:
    ///   | 1.2 | Sequences and their limits | 37 (problems p. 49) |
    ///   | 3 | Proving statements | 39 | 3.1 p. 40, 3.2 p. 45, … |
    static func pageMap(from table: Table) -> [NotesSection] {
        var sections: [NotesSection] = []
        for row in table.rows where row.count >= 3 {
            let label = row[0]
            let title = row[1]
            let pageCell = row[2]
            if row.count >= 4, !row[3].isEmpty {
                let subsections = row[3].allMatches(#"(\d+\.\d+)\s+p\.\s*(\d+)"#)
                if !subsections.isEmpty {
                    for match in subsections {
                        sections.append(NotesSection(section: match[1], title: title, page: Int(match[2]) ?? 0))
                    }
                    continue
                }
                if let range = row[3].firstMatch(#"(\d+\.\d+)\s*[–-]\s*(\d+\.\d+),\s*pp\.\s*(\d+)"#) {
                    sections.append(NotesSection(section: label, title: "\(title) (\(range[1])–\(range[2]))", page: Int(range[3]) ?? 0))
                    continue
                }
            }
            guard let page = pageCell.firstMatch(#"^(\d+)"#).flatMap({ Int($0[1]) }) else { continue }
            let problems = pageCell.firstMatch(#"problems p\.\s*(\d+)"#).flatMap { Int($0[1]) }
            sections.append(NotesSection(section: label, title: title, page: page, problemsPage: problems))
        }
        return sections.sorted { $0.page < $1.page }
    }
}
