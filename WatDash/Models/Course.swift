//
//  Course.swift
//  WatDash
//

import Foundation

/// A course this term. The course code ("MATH 137") is the join key that ties
/// events, assessments, study pages and the local course folder together.
struct Course: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var code: String
    var title: String = ""
    var units: Double = 0.5
    var colorIndex: Int = 0
    /// Absolute path of the course folder (the one holding its CLAUDE.md).
    var folderPath: String?
    /// CR/NCR courses and PD courses don't count toward the average.
    var countsTowardAverage: Bool = true
    var scheme: GradeScheme = GradeScheme()
    var studyLinks: [StudyLink] = []
    var pageMap: [NotesSection] = []
    /// PDF of the course notes, relative to the folder.
    var notesFile: String?
    /// Course-specific rule the study generator must respect, e.g. MATH 135's
    /// "teach with different examples, never hand over assignment answers".
    var teachDontAnswer: Bool = false
    var sections: [String] = []  // e.g. ["LEC 005", "TUT 104"]
    var notes: String?

    var subject: String { code.split(separator: " ").first.map(String.init) ?? code }
    var catalogNumber: String { code.split(separator: " ").dropFirst().joined(separator: " ") }

    var displayTitle: String { title.isEmpty ? code : "\(code) · \(title)" }

    var folderURL: URL? { folderPath.map { URL(fileURLWithPath: $0) } }

    var notesURL: URL? {
        guard let folderURL, let notesFile else { return nil }
        return folderURL.appendingPathComponent(notesFile)
    }
}

/// A study page or reference link (artifact URL, local HTML build, LEARN page).
struct StudyLink: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var url: String
    var note: String?

    var isLocalFile: Bool { url.hasPrefix("/") || url.hasPrefix("file://") }

    var resolvedURL: URL? {
        if url.hasPrefix("/") { return URL(fileURLWithPath: url) }
        return URL(string: url)
    }
}

/// One row of a course's notes page map: section "1.2" starts on page 37.
struct NotesSection: Identifiable, Codable, Hashable, Sendable {
    var id: String { section }
    var section: String
    var title: String
    var page: Int
    var problemsPage: Int?
}

/// Normalization for course codes typed or parsed in every possible shape:
/// "math137", "MATH-137", "Math 137" → "MATH 137".
enum CourseCode {
    static let pattern = #"\b([A-Za-z]{2,6})[ \-]?([0-9]{3}[A-Za-z]?)\b"#

    static func normalize(_ raw: String) -> String? {
        guard let groups = raw.firstMatch(pattern), groups.count >= 3 else { return nil }
        let subject = groups[1].uppercased()
        // Words that look like subjects but aren't ("Room 2034", "Page 123").
        let stop: Set<String> = ["ROOM", "PAGE", "PAGES", "WEEK", "UNIT", "PP", "AT", "IN", "ON", "BY", "AND", "THE", "FOR", "PM", "AM"]
        guard !stop.contains(subject) else { return nil }
        return "\(subject) \(groups[2].uppercased())"
    }

    /// Finds a known course code inside free text.
    static func find(in text: String, among known: [String]) -> String? {
        let upper = text.uppercased()
        for code in known {
            let compact = code.replacingOccurrences(of: " ", with: "")
            if upper.contains(code) || upper.contains(compact) || upper.contains(code.replacingOccurrences(of: " ", with: "-")) {
                return code
            }
        }
        for match in text.allMatches(pattern) where match.count >= 3 {
            if let code = normalize(match[0]) { return code }
        }
        return nil
    }
}
