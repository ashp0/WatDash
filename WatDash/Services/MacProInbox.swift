//
//  MacProInbox.swift
//  WatDash
//

import Foundation

/// Notes from the Mac Pro. Syllabus never edits WatDash's data: a change made
/// there becomes one small new file in the repository's `Inbox/`, which
/// WatDash applies, deletes and answers in the next export.
///
///     done: assessment:6F1D2C4A-…
///     written: 2026-10-10 14:03
///     from: Syllabus on the Mac Pro
///
/// The first `capture:`, `done:` or `undone:` line is the note; `written:`
/// (Waterloo time) dates a capture's "tomorrow"; anything else is ignored.
/// Pure, and checked in `Tests/Checks.swift`.
enum MacProInbox {
    enum Action: Hashable {
        /// One quick-capture line, as typed.
        case capture(String)
        /// An export id ("assessment:<uuid>") to tick or untick.
        case done(String)
        case undone(String)
    }

    struct Note: Hashable {
        var action: Action
        var written: Date?
    }

    static let folder = "Inbox"

    /// A note's own file: `Inbox/<name>.txt`, nothing hidden, nothing nested.
    static func isNotePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == Substring(folder) else { return false }
        let name = String(parts[1])
        return name.hasSuffix(".txt") && !name.hasPrefix(".") && name.count > 4 && name.count <= 120
    }

    static func parse(_ text: String) -> Note? {
        var action: Action?
        var written: Date?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmed
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmed.lowercased()
            let value = String(line[line.index(after: colon)...]).trimmed
            switch key {
            case "capture" where action == nil && !value.isEmpty: action = .capture(value)
            case "done" where action == nil && !value.isEmpty: action = .done(value)
            case "undone" where action == nil && !value.isEmpty: action = .undone(value)
            case "written": written = MacProExport.date(fromStamp: value)
            default: break
            }
        }
        return action.map { Note(action: $0, written: written) }
    }

    /// The note's first line, as the export's log repeats it.
    static func summary(_ text: String) -> String {
        let first = text.components(separatedBy: .newlines).map(\.trimmed).first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
        return String(first.prefix(300))
    }

    /// The assessment an exported deadline id names ("assessment:<uuid>").
    static func assessmentIndex(forExportID id: String, in assessments: [Assessment]) -> Int? {
        let prefix = "assessment:"
        guard id.hasPrefix(prefix), let uuid = UUID(uuidString: String(id.dropFirst(prefix.count)).trimmed) else { return nil }
        return assessments.firstIndex { $0.id == uuid }
    }

    /// Applies a tick to a copy of the assessments. Nil when nothing has that id.
    static func settingDone(_ done: Bool, id: String, in assessments: [Assessment]) -> (assessments: [Assessment], message: String)? {
        guard let index = assessmentIndex(forExportID: id, in: assessments) else { return nil }
        var changed = assessments
        changed[index].isDone = done
        let item = changed[index]
        return (changed, "\(item.courseCode) \(item.title) marked \(done ? "done" : "not done").")
    }
}
