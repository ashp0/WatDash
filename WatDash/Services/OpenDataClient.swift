//
//  OpenDataClient.swift
//  WatDash
//

import Foundation

/// University of Waterloo Open Data API v3 (openapi.data.uwaterloo.ca).
///
/// Needs a free key (register once with your email). Everything is decoded
/// leniently — every field optional — because the schema is documented but
/// not always honoured, and one surprising null must not sink an import.
/// The paid-holidays feed is the exception: it's anonymous, so holidays work
/// before you have a key.
struct OpenDataClient {
    static let base = URL(string: "https://openapi.data.uwaterloo.ca/v3/")!
    static let holidaysFeed = URL(string: "https://openapi.data.uwaterloo.ca/v3/HolidayDates/paidholidays/ics")!
    static let registrationPage = URL(string: "https://openapi.data.uwaterloo.ca/api-docs/index.html")!

    var apiKey: String?

    enum ClientError: LocalizedError {
        case missingKey, http(Int, String), decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Open Data API key in Settings → Integrations first."
            case let .http(code, message): "Open Data API returned \(code): \(message)"
            case let .decoding(detail): "Couldn't read the Open Data response (\(detail))."
            }
        }
    }

    // MARK: - Models

    struct Term: Decodable, Sendable {
        var termCode: String?
        var name: String?
        var termBeginDate: String?
        var termEndDate: String?
    }

    struct ClassSection: Decodable, Sendable, Identifiable {
        var id: String { "\(courseComponent ?? "")-\(classSection ?? 0)-\(classNumber ?? 0)" }
        var courseId: String?
        var classSection: Int?
        var classNumber: Int?
        var courseComponent: String?
        var maxEnrollmentCapacity: Int?
        var enrolledStudents: Int?
        var scheduleData: [Meeting]?
        var instructorData: [Instructor]?

        var sectionLabel: String { String(format: "%03d", classSection ?? 0) }
    }

    struct Meeting: Decodable, Sendable {
        var scheduleStartDate: String?
        var scheduleEndDate: String?
        var classMeetingStartTime: String?
        var classMeetingEndTime: String?
        var classMeetingDayPatternCode: String?
        var locationName: String?
    }

    struct Instructor: Decodable, Sendable {
        var instructorFirstName: String?
        var instructorLastName: String?
    }

    struct ImportantDate: Decodable, Sendable {
        var name: String?
        var description: String?
        var details: [Detail]?

        struct Detail: Decodable, Sendable {
            var termName: String?
            var startDate: String?
            var endDate: String?
        }
    }

    struct Exam: Decodable, Sendable {
        var examDisplayName: String?
        var sections: String?
        var day: String?
        var location: String?
        var examWindowStartDate: String?
        var examWindowStartTime: String?
        var examDuration: String?
    }

    struct SiteEvent: Decodable, Sendable, Identifiable {
        var id: String { uniqueKey ?? title ?? UUID().uuidString }
        var uniqueKey: String?
        var title: String?
        var eventStartDate: String?
        var eventEndDate: String?
        var eventTimezone: String?
        var itemUri: String?
        var eventWebsite: String?
        var eventTags: String?
        var locationName: String?
        var host: String?
    }

    // MARK: - Calls

    func currentTerm() async throws -> Term { try await get("Terms/current") }

    func classes(term: String, subject: String, catalog: String) async throws -> [ClassSection] {
        try await get("ClassSchedules/\(term)/\(subject)/\(catalog)")
    }

    func importantDates() async throws -> [ImportantDate] { try await get("ImportantDates") }

    func exams(term: String) async throws -> [Exam] { try await get("ExamSchedules/\(term)") }

    func latestEvents(_ count: Int = 40) async throws -> [SiteEvent] { try await get("Wcms/latestevents/\(count)") }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.missingKey }
        var request = URLRequest(url: OpenDataClient.base.appendingPathComponent(path))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["Message"] as? String
            throw ClientError.http(code, message ?? String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError.decoding(String(describing: error).prefix(160).description)
        }
    }

    // MARK: - Conversions

    /// API date-times come as "2026-09-09T00:00:00" (no zone): Waterloo time.
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Waterloo.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    static func minutes(_ raw: String?) -> Int? {
        guard let date = date(raw) else { return nil }
        let parts = Waterloo.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func meetings(for section: ClassSection, courseCode: String) -> [ParsedMeeting] {
        (section.scheduleData ?? []).compactMap { meeting in
            guard let start = minutes(meeting.classMeetingStartTime),
                  let end = minutes(meeting.classMeetingEndTime),
                  let pattern = meeting.classMeetingDayPatternCode else { return nil }
            let instructor = section.instructorData?.first.map { "\($0.instructorFirstName ?? "") \($0.instructorLastName ?? "")".trimmed }
            let first = date(meeting.scheduleStartDate)
            let last = date(meeting.scheduleEndDate)
            return ParsedMeeting(
                courseCode: courseCode, courseTitle: nil, component: section.courseComponent, section: section.sectionLabel,
                weekdays: MeetingText.weekdays(from: pattern), startMinutes: start, endMinutes: end,
                location: meeting.locationName?.nilIfEmpty, instructor: instructor?.nilIfEmpty,
                firstDay: first, lastDay: last
            )
        }
    }
}
