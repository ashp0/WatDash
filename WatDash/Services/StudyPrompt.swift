//
//  StudyPrompt.swift
//  WatDash
//

import Foundation

/// Builds a ready-to-paste Claude Code prompt for a study page.
///
/// No API key needed: the page is made by Claude Code on your subscription,
/// inside the classes folder, where the `quiz-prep` skill and its three agents
/// (notes-reader, past-paper-scout, solution-checker) already live. WatDash's
/// job is the part that's tedious to type: which assessment, when, which
/// sections, which notes pages, which page to extend and which course rules
/// apply. It copies the prompt; you paste it into Claude Code.
struct StudyPrompt {
    struct Options: Hashable {
        var practicePerSection = 4
        var mockQuiz = true
        var pastPapers = true
        var extendExisting = true
        var extraInstructions = ""
    }

    var course: Course
    var sections: [NotesSection]
    var assessment: Assessment?
    var classesRoot: String
    var options = Options()

    /// Printed page range for each chosen section, from the course page map.
    func pageRanges() -> [(NotesSection, ClosedRange<Int>)] {
        let map = course.pageMap.sorted { $0.page < $1.page }
        return sections.sorted { $0.page < $1.page }.map { section in
            let following = map.first { $0.page > section.page }?.page
            let end = max(section.page, (following ?? section.page + 10) - 1)
            return (section, section.page...end)
        }
    }

    var existingArtifact: StudyLink? {
        course.studyLinks.last { $0.url.contains("claude.ai/") }
    }

    var folderName: String {
        course.folderURL?.lastPathComponent ?? course.code.replacingOccurrences(of: " ", with: "")
    }

    var text: String {
        var lines: [String] = []
        let what: String
        if let assessment {
            var when = ""
            if let due = assessment.due {
                when = " (\(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(due.formatted(date: .omitted, time: .shortened)))"
            }
            what = "\(course.code) \(assessment.title)\(when)"
            lines.append("Use the quiz-prep skill to build a study page for \(what).")
        } else {
            what = "\(course.code) " + sections.map { "§\($0.section)" }.joined(separator: ", ")
            lines.append("Use the quiz-prep skill to build a study page for \(what), for catching up rather than a specific quiz.")
        }
        lines.append("")
        lines.append("Read \(folderName)/CLAUDE.md first and follow its rules for helping in this course.")

        if !sections.isEmpty {
            let notes = course.notesFile.map { "\(folderName)/\($0)" } ?? "the course notes PDF"
            lines.append("")
            lines.append("Cover these sections of \(notes):")
            for (section, pages) in pageRanges() {
                let problems = section.problemsPage.map { ", problems p. \($0)" } ?? ""
                lines.append("- §\(section.section) \(section.title) (pp. \(pages.lowerBound)–\(pages.upperBound)\(problems))")
            }
        } else if let coverage = assessment?.coverage {
            lines.append("")
            lines.append("It covers notes sections \(coverage).")
        }

        lines.append("")
        var include = ["short notes per section", "\(options.practicePerSection) practice problems per section with hints and solutions hidden"]
        if options.mockQuiz { include.append("a timed mock quiz in the real format") }
        include.append("model solutions for the course-notes problems in these sections")
        lines.append("Include " + Self.list(include) + ".")
        if options.pastPapers {
            lines.append("Have past-paper-scout look for past versions of this assessment, and say where each finding came from.")
        }
        lines.append("Have solution-checker re-solve every problem before publishing.")

        if course.teachDontAnswer {
            lines.append("")
            lines.append("This course has a strict rule: teach with examples that differ from the assignments, and don't repeat or hint at any assignment question.")
        }

        if options.extendExisting, let page = existingArtifact {
            lines.append("")
            lines.append("Extend the existing \(page.title) page (\(page.url)) instead of starting a new one: add these topics, move the “next” date card forward, rebuild, check, and republish to the same URL.")
        }

        let extra = options.extraInstructions.trimmed
        if !extra.isEmpty {
            lines.append("")
            lines.append(extra)
        }

        lines.append("")
        lines.append("When it's published, give me the link and update the Study pages section of \(folderName)/CLAUDE.md.")
        return lines.joined(separator: "\n")
    }

    /// `cd "<classes folder>" && claude '<prompt>'`, for pasting into Terminal.
    var terminalCommand: String {
        let quoted = "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let folder = "\"" + classesRoot.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return "cd \(folder) && claude \(quoted)"
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    /// Sections an assessment's coverage mentions ("1.4–1.5, 2.1" → 1.4, 1.5, 2.1).
    static func sections(for coverage: String?, in map: [NotesSection]) -> [NotesSection] {
        guard let coverage else { return [] }
        var wanted: [NotesSection] = []
        for part in coverage.components(separatedBy: CharacterSet(charactersIn: ",;")) {
            let piece = part.trimmed
            if let range = piece.firstMatch(#"(\d+\.\d+)\s*[–-]\s*(\d+\.\d+)"#) {
                wanted += map.filter { inRange($0.section, range[1], range[2]) }
            } else if let single = piece.firstMatch(#"^(\d+\.\d+)$"#) {
                wanted += map.filter { $0.section == single[1] }
            }
        }
        var seen = Set<String>()
        return wanted.filter { seen.insert($0.section).inserted }
    }

    /// "1.4–2.1" spans chapters; compare as (chapter, section) pairs so 1.10
    /// sorts after 1.9 rather than before 1.2.
    private static func inRange(_ section: String, _ low: String, _ high: String) -> Bool {
        func pair(_ text: String) -> (Int, Int) {
            let parts = text.split(separator: ".").compactMap { Int($0) }
            return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
        }
        let s = pair(section), l = pair(low), h = pair(high)
        return (s.0, s.1) >= (l.0, l.1) && (s.0, s.1) <= (h.0, h.1)
    }
}
