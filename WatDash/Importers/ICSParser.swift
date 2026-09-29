//
//  ICSParser.swift
//  WatDash (from WatAlarm)
//

import Foundation

/// A small, dependency-free RFC 5545 (iCalendar) parser covering the subset
/// that university schedule exports actually use.
///
/// Parsing ourselves (instead of opening the file in Calendar) is what makes a
/// re-import idempotent: every event keeps its UID, so importing a corrected
/// Quest export updates the term in place instead of duplicating it.
///
/// Scope, stated plainly: VEVENT with DTSTART/DTEND/DURATION, SUMMARY,
/// LOCATION, DESCRIPTION, UID, RRULE (FREQ/INTERVAL/COUNT/UNTIL/BYDAY) and
/// EXDATE. VTIMEZONE bodies are not interpreted — TZID values are resolved as
/// IANA identifiers, which is what every exporter in practice emits.
enum ICSParser {

    // MARK: - Output

    struct ParsedEvent: Sendable, Identifiable {
        var id: String { uid }
        var uid: String
        var summary: String
        var location: String?
        var notes: String?
        var start: Date
        var end: Date
        var isAllDay: Bool
        var timeZone: TimeZone?
        var recurrence: Recurrence?
        var exceptionDates: [Date]
        var isCancelled: Bool = false
        var url: String?
    }

    struct Recurrence: Sendable, Equatable {
        enum Frequency: String, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }
        var frequency: Frequency
        var interval: Int
        var count: Int?
        var until: Date?
        /// Weekday numbers in `Calendar` terms (1 = Sunday).
        var weekdays: [Int]
    }

    enum ParseError: LocalizedError {
        case notCalendarData
        case noEvents

        var errorDescription: String? {
            switch self {
            case .notCalendarData: "That file doesn’t look like a calendar (.ics) file."
            case .noEvents: "No events were found in that calendar file."
            }
        }
    }

    // MARK: - Entry point

    static func parse(_ text: String) throws -> [ParsedEvent] {
        guard text.contains("BEGIN:VCALENDAR") || text.contains("BEGIN:VEVENT") else {
            throw ParseError.notCalendarData
        }

        var events: [ParsedEvent] = []
        var currentLines: [ContentLine]?

        for line in unfold(text) {
            let parsed = ContentLine(rawLine: line)

            switch (parsed.name, parsed.value) {
            case ("BEGIN", "VEVENT"):
                currentLines = []
            case ("END", "VEVENT"):
                if let lines = currentLines, let event = makeEvent(from: lines) {
                    events.append(event)
                }
                currentLines = nil
            default:
                currentLines?.append(parsed)
            }
        }

        guard !events.isEmpty else { throw ParseError.noEvents }
        return events.sorted { $0.start < $1.start }
    }

    // MARK: - Line handling

    /// RFC 5545 §3.1: a line break followed by a space or tab is a
    /// continuation. Exporters wrap at 75 octets, so long SUMMARY/LOCATION
    /// values are routinely folded — failing to unfold corrupts course titles.
    private static func unfold(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [String] = []
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = rawLine.first, first == " " || first == "\t" {
                let continuation = String(rawLine.dropFirst())
                if result.isEmpty {
                    result.append(continuation)
                } else {
                    result[result.count - 1] += continuation
                }
            } else if !rawLine.isEmpty {
                result.append(String(rawLine))
            }
        }
        return result
    }

    /// One `NAME;PARAM=value:VALUE` line.
    private struct ContentLine {
        var name: String
        var parameters: [String: String]
        var value: String

        init(rawLine: String) {
            // Split on the first colon that is not inside a quoted parameter.
            var insideQuotes = false
            var colonIndex: String.Index?
            var index = rawLine.startIndex
            while index < rawLine.endIndex {
                let character = rawLine[index]
                if character == "\"" { insideQuotes.toggle() }
                if character == ":" && !insideQuotes {
                    colonIndex = index
                    break
                }
                index = rawLine.index(after: index)
            }

            guard let colonIndex else {
                name = rawLine.uppercased()
                parameters = [:]
                value = ""
                return
            }

            let head = String(rawLine[rawLine.startIndex..<colonIndex])
            value = String(rawLine[rawLine.index(after: colonIndex)...])

            let headParts = head.split(separator: ";").map(String.init)
            name = (headParts.first ?? "").uppercased()

            var params: [String: String] = [:]
            for part in headParts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            parameters = params
        }
    }

    // MARK: - Event assembly

    private static func makeEvent(from lines: [ContentLine]) -> ParsedEvent? {
        var uid = UUID().uuidString
        var summary = "Untitled"
        var location: String?
        var notes: String?
        var start: Date?
        var end: Date?
        var duration: DateComponents?
        var isAllDay = false
        var timeZone: TimeZone?
        var recurrence: Recurrence?
        var exceptions: [Date] = []
        var isCancelled = false
        var url: String?

        for line in lines {
            switch line.name {
            case "UID":
                uid = line.value
            case "SUMMARY":
                summary = unescape(line.value)
            case "LOCATION":
                location = unescape(line.value).nilIfEmpty
            case "DESCRIPTION":
                notes = unescape(line.value).nilIfEmpty
            case "DTSTART":
                let parsed = parseDate(line)
                start = parsed.date
                isAllDay = parsed.isDateOnly
                timeZone = parsed.timeZone
            case "DTEND":
                end = parseDate(line).date
            case "DURATION":
                duration = parseDuration(line.value)
            case "STATUS":
                isCancelled = line.value.uppercased() == "CANCELLED"
            case "URL":
                url = line.value.nilIfEmpty
            case "RRULE":
                recurrence = parseRecurrence(line.value, timeZone: timeZone)
            case "EXDATE":
                // EXDATE can carry a comma-separated list.
                for component in line.value.split(separator: ",") {
                    var copy = line
                    copy.value = String(component)
                    if let date = parseDate(copy).date { exceptions.append(date) }
                }
            default:
                break
            }
        }

        guard let start else { return nil }

        let resolvedEnd: Date
        if let end {
            resolvedEnd = end
        } else if let duration {
            resolvedEnd = Calendar.current.date(byAdding: duration, to: start) ?? start.addingTimeInterval(3600)
        } else {
            // RFC 5545: a DTSTART with no DTEND/DURATION is a zero-length
            // instant for date-time values, and one day for date values.
            resolvedEnd = isAllDay ? start.addingTimeInterval(86_400) : start.addingTimeInterval(3600)
        }

        return ParsedEvent(
            uid: uid,
            summary: summary,
            location: location,
            notes: notes,
            start: start,
            end: resolvedEnd,
            isAllDay: isAllDay,
            timeZone: timeZone,
            recurrence: recurrence,
            exceptionDates: exceptions,
            isCancelled: isCancelled,
            url: url
        )
    }

    // MARK: - Values

    /// Handles the three DATE-TIME forms in the wild:
    ///   20260908T103000Z          — UTC
    ///   TZID=America/Toronto:...  — zoned local time
    ///   20260908T103000           — floating (interpreted in device time zone)
    /// plus VALUE=DATE (20260908) for all-day events.
    private static func parseDate(_ line: ContentLine) -> (date: Date?, isDateOnly: Bool, timeZone: TimeZone?) {
        let raw = line.value.trimmingCharacters(in: .whitespaces)
        let isDateOnly = line.parameters["VALUE"] == "DATE" || (raw.count == 8 && !raw.contains("T"))

        var zone: TimeZone?
        if let tzid = line.parameters["TZID"] {
            zone = TimeZone(identifier: tzid) ?? TimeZone(abbreviation: tzid)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        if isDateOnly {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = zone ?? .current
            return (formatter.date(from: raw), true, zone)
        }

        if raw.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return (formatter.date(from: raw), false, TimeZone(secondsFromGMT: 0))
        }

        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = zone ?? .current
        return (formatter.date(from: raw), false, zone)
    }

    /// Minimal ISO 8601 duration parsing: P[n]DT[n]H[n]M[n]S and P[n]W.
    private static func parseDuration(_ value: String) -> DateComponents? {
        guard value.hasPrefix("P") else { return nil }
        var components = DateComponents()
        var number = ""
        var inTimeSection = false

        for character in value.dropFirst() {
            if character == "T" { inTimeSection = true; continue }
            if character.isNumber { number.append(character); continue }

            let amount = Int(number) ?? 0
            number = ""
            switch character {
            case "W": components.day = (components.day ?? 0) + amount * 7
            case "D": components.day = (components.day ?? 0) + amount
            case "H": components.hour = amount
            case "M":
                // "M" means minutes after the T separator and months before it.
                if inTimeSection { components.minute = amount } else { components.month = amount }
            case "S": components.second = amount
            default: break
            }
        }
        return components
    }

    private static func parseRecurrence(_ value: String, timeZone: TimeZone?) -> Recurrence? {
        var parts: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            parts[kv[0].uppercased()] = kv[1]
        }

        guard let frequency = parts["FREQ"].flatMap({ Recurrence.Frequency(rawValue: $0.uppercased()) }) else {
            return nil
        }

        var until: Date?
        if let rawUntil = parts["UNTIL"] {
            var line = ContentLine(rawLine: "UNTIL:\(rawUntil)")
            if !rawUntil.hasSuffix("Z"), let timeZone {
                line = ContentLine(rawLine: "UNTIL;TZID=\(timeZone.identifier):\(rawUntil)")
            }
            until = parseDate(line).date
        }

        let dayMap: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let weekdays: [Int] = (parts["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { token in
                // BYDAY entries may carry an ordinal prefix ("2MO"); schedule
                // exports don't, but strip it defensively.
                let letters = String(token.suffix(2)).uppercased()
                return dayMap[letters]
            }

        return Recurrence(
            frequency: frequency,
            interval: parts["INTERVAL"].flatMap(Int.init) ?? 1,
            count: parts["COUNT"].flatMap(Int.init),
            until: until,
            weekdays: weekdays
        )
    }

    /// RFC 5545 §3.3.11 text escaping.
    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
