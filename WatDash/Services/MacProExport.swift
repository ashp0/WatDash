//
//  MacProExport.swift
//  WatDash
//

import Foundation

/// The calendar the Mac Pro shows: `Calendar/watdash.json` in the classes
/// repository, read by Syllabus on OS X 10.9.
///
/// WatDash has already done every hard part — recurrence, holidays and
/// reading week, skipped lectures, test slots an assessment replaces, done
/// ticks, coverage mapped to notes pages — so the file holds only dated,
/// final things the Mac Pro draws as they are. Times are Waterloo wall-clock
/// strings ("2026-10-19 17:30"), which a 10.9 app compares as plain numbers.
///
/// Pure: no store, no clock, no files. `Tests/Checks.swift` covers it. The
/// format is documented in the README ("The Mac Pro") and in Syllabus's.
enum MacProExport {
    static let format = "watdash-calendar"
    static let version = 1

    struct Input {
        var courses: [Course]
        var events: [DashEvent]
        var assessments: [Assessment]
        var termName: String
        var termEnd: Date
        /// The classes folder (the repository root), so course folders and
        /// notes PDFs can be given relative to it.
        var classesFolder: String
        /// WatDash's office-hours switch: off leaves office hours out.
        var officeHours: Bool
        /// Course colours by index (Palette.courses).
        var palette: [(Double, Double, Double)]
        /// What happened to the notes the Mac Pro left in Inbox/.
        var notes: [NoteLog]
        var now: Date
    }

    struct Document: Codable, Equatable {
        var format: String
        var version: Int
        /// When this content was first written. Not part of the comparison
        /// that decides whether anything changed.
        var exported: String
        var timeZone: String
        var term: String
        var from: String
        var to: String
        var officeHours: Bool
        var courses: [CourseEntry]
        var classes: [ClassEntry]
        var allDay: [AllDayEntry]
        var deadlines: [DeadlineEntry]
        var notes: [NoteLog]
    }

    struct CourseEntry: Codable, Equatable {
        var code: String
        var title: String?
        var color: String
        /// The course's folder in the repository ("Math137").
        var folder: String?
        /// The notes PDF, from the repository root ("Math137/MATH_137.pdf").
        var notesFile: String?
    }

    struct ClassEntry: Codable, Equatable {
        var id: String
        var course: String?
        var title: String
        var kind: String
        var start: String
        var end: String
        var room: String?
    }

    struct AllDayEntry: Codable, Equatable {
        var id: String
        var course: String?
        var title: String
        var kind: String
        /// First and last day, inclusive.
        var first: String
        var last: String
    }

    struct SectionEntry: Codable, Equatable {
        var section: String
        var title: String
        var page: Int
    }

    struct DeadlineEntry: Codable, Equatable {
        var id: String
        var course: String?
        var title: String
        var kind: String
        /// Missing when the date isn't known yet (TBA).
        var due: String?
        /// The end of the writing window; missing for a point in time.
        var end: String?
        var covers: String?
        var room: String?
        var seat: String?
        var detail: String?
        var done: Bool
        /// The Mac Pro may tick it: a WatDash assessment without a mark.
        var canTick: Bool
        /// Written in an assigned seat, which Odyssey shows.
        var seated: Bool
        /// The notes sections it covers, with their first pages.
        var sections: [SectionEntry]?
    }

    /// One note from the Mac Pro, and what WatDash did with it.
    struct NoteLog: Codable, Equatable, Hashable {
        /// Its path in the repository ("Inbox/2026-10-10-140312-1a2b3c.txt").
        var file: String
        /// The note itself ("done: assessment:…").
        var note: String
        /// applied, inbox (a capture waiting to be confirmed in WatDash),
        /// unknown (no such item), failed or unreadable.
        var result: String
        var message: String
        var when: String
    }

    // MARK: - Building

    /// From the Monday of last week to the end of exams (or the last dated
    /// assessment, or three weeks ahead, whichever is latest).
    static func window(now: Date, termEnd: Date, assessments: [Assessment]) -> DateInterval {
        let calendar = Waterloo.calendar
        let start = calendar.startOfWeek(for: now.addingTimeInterval(-7 * 86_400))
        var last = max(termEnd, now.addingTimeInterval(21 * 86_400))
        for assessment in assessments {
            if let end = assessment.agendaEnd ?? assessment.due { last = max(last, end) }
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        return DateInterval(start: start, end: end)
    }

    static func document(_ input: Input, exported: String) -> Document {
        let window = window(now: input.now, termEnd: input.termEnd, assessments: input.assessments)
        let items = RecurrenceExpander.agenda(
            events: input.events.filter { $0.status == .confirmed },
            assessments: input.assessments,
            in: window
        )
        let assessments = Dictionary(input.assessments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let courses = Dictionary(input.courses.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })

        var classes: [ClassEntry] = []
        var allDay: [AllDayEntry] = []
        var deadlines: [DeadlineEntry] = []
        for item in items {
            if item.kind == .officeHours && !input.officeHours { continue }
            if item.isAllDay {
                let lastInstant = item.end > item.start ? item.end.addingTimeInterval(-1) : item.start
                allDay.append(AllDayEntry(id: item.id, course: item.courseCode, title: item.title, kind: item.kind.rawValue,
                                          first: day(item.start), last: day(lastInstant)))
            } else if item.kind.isAssessment || item.kind.isDue {
                var assessment: Assessment?
                if case let .assessment(id) = item.origin { assessment = assessments[id] }
                deadlines.append(deadline(item: item, assessment: assessment, course: courses[item.courseCode ?? ""]))
            } else {
                classes.append(ClassEntry(id: item.id, course: item.courseCode, title: item.title, kind: item.kind.rawValue,
                                          start: stamp(item.start), end: stamp(item.end), room: item.location?.nilIfEmpty))
            }
        }
        // Undated work (finals before the Registrar posts them) has no
        // agenda item, but belongs on its course's tab.
        for assessment in input.assessments where assessment.due == nil && !assessment.isGraded {
            let (room, seat) = roomAndSeat(assessment.location)
            deadlines.append(DeadlineEntry(
                id: "assessment:\(assessment.id.uuidString)", course: assessment.courseCode, title: assessment.title,
                kind: assessment.kind.rawValue, due: nil, end: nil, covers: assessment.coverage?.nilIfEmpty,
                room: room, seat: seat, detail: nil, done: assessment.isDone, canTick: true, seated: assessment.kind.isSeated,
                sections: sections(assessment.coverage, course: courses[assessment.courseCode])))
        }

        let byStart: (String?, String, String?, String) -> Bool = { lhsStart, lhsID, rhsStart, rhsID in
            let l = lhsStart ?? "9999", r = rhsStart ?? "9999"
            return l != r ? l < r : lhsID < rhsID
        }
        classes.sort { byStart($0.start, $0.id, $1.start, $1.id) }
        allDay.sort { byStart($0.first, $0.id, $1.first, $1.id) }
        deadlines.sort { byStart($0.due, $0.id, $1.due, $1.id) }

        let courseEntries = input.courses.sorted { $0.code < $1.code }.map { course in
            CourseEntry(code: course.code, title: course.title.nilIfEmpty, color: hex(course.colorIndex, input.palette),
                        folder: relative(course.folderPath, to: input.classesFolder),
                        notesFile: relative(course.notesURL?.path, to: input.classesFolder))
        }

        return Document(
            format: format, version: version, exported: exported, timeZone: Waterloo.timeZone.identifier,
            term: input.termName, from: day(window.start), to: day(window.end.addingTimeInterval(-1)),
            officeHours: input.officeHours, courses: courseEntries, classes: classes, allDay: allDay,
            deadlines: deadlines, notes: Array(input.notes.sorted { $0.file < $1.file }.suffix(100))
        )
    }

    private static func deadline(item: AgendaItem, assessment: Assessment?, course: Course?) -> DeadlineEntry {
        let (room, seat) = roomAndSeat(item.location)
        let pointInTime = item.isDue || item.end <= item.start
        return DeadlineEntry(
            id: item.id, course: item.courseCode, title: item.title, kind: item.kind.rawValue,
            due: stamp(item.start), end: pointInTime ? nil : stamp(item.end),
            covers: assessment?.coverage?.nilIfEmpty, room: room, seat: seat,
            detail: assessment == nil ? item.detail?.nilIfEmpty : nil,
            done: item.isDone, canTick: assessment.map { !$0.isGraded } ?? false, seated: item.kind.isSeated,
            sections: sections(assessment?.coverage, course: course))
    }

    private static func sections(_ coverage: String?, course: Course?) -> [SectionEntry]? {
        guard let course, !course.pageMap.isEmpty else { return nil }
        let found = StudyPrompt.sections(for: coverage, in: course.pageMap)
        return found.isEmpty ? nil : found.map { SectionEntry(section: $0.section, title: $0.title, page: $0.page) }
    }

    // MARK: - Encoding

    /// Pretty, key-sorted JSON, so the same calendar is the same bytes and a
    /// commit diff shows what changed.
    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(0x0A)
        return data
    }

    static func decode(_ data: Data) -> Document? {
        try? JSONDecoder().decode(Document.self, from: data)
    }

    /// Whether two exports say the same thing, whenever each was written.
    static func sameContent(_ a: Document, _ b: Document) -> Bool {
        var a = a, b = b
        a.exported = ""
        b.exported = ""
        return a == b
    }

    // MARK: - Helpers

    /// "MC 1085, seat E-14" → room "MC 1085", seat "E-14".
    static func roomAndSeat(_ location: String?) -> (room: String?, seat: String?) {
        guard let text = location?.trimmed.nilIfEmpty else { return (nil, nil) }
        if let match = text.firstMatch(#"^(.*?)[,;]?\s*\bseat\b[:#\s]*(\S.*)$"#, options: .caseInsensitive) {
            return (match[1].trimmed.nilIfEmpty, match[2].trimmed.nilIfEmpty)
        }
        return (text, nil)
    }

    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func date(fromStamp text: String) -> Date? {
        stampFormatter.date(from: text.trimmed)
    }

    private static let stampFormatter: DateFormatter = formatter("yyyy-MM-dd HH:mm")
    private static let dayFormatter: DateFormatter = formatter("yyyy-MM-dd")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Waterloo.timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func hex(_ index: Int, _ palette: [(Double, Double, Double)]) -> String {
        guard !palette.isEmpty else { return "#808080" }
        let rgb = palette[((index % palette.count) + palette.count) % palette.count]
        let byte = { (value: Double) in Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.0), byte(rgb.1), byte(rgb.2))
    }

    /// `path` relative to `root`, or nil when it isn't inside it.
    static func relative(_ path: String?, to root: String) -> String? {
        guard let path = path?.nilIfEmpty else { return nil }
        let base = (root as NSString).standardizingPath
        let full = (path as NSString).standardizingPath
        guard full.hasPrefix(base + "/") else { return nil }
        return String(full.dropFirst(base.count + 1))
    }
}
