//
//  WidgetSnapshot.swift
//  WatDash
//

import Foundation

/// Everything the widgets show, precomputed by the app and written to the App
/// Group container. The widget extension never touches the store: it renders
/// this file, and builds timeline entries at each item's start and end so
/// "Up next" advances on its own between app launches.
struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var courseCode: String?
        var colorIndex: Int?
        var kindLabel: String
        var symbol: String
        var start: Date
        var end: Date
        var location: String?
        var isDue: Bool
        var isClass: Bool
        var isAssessment: Bool
        var detail: String?
    }

    struct Average: Codable, Hashable, Sendable {
        var projected: Double?
        var low: Double?
        var high: Double?
        var floor: Double?
        var target: Double
        var probability: Double?
        var required: String
        var courses: [CourseLine]
    }

    struct CourseLine: Codable, Hashable, Sendable, Identifiable {
        var id: String { code }
        var code: String
        var colorIndex: Int
        var current: Double?
        var projected: Double?
    }

    var generatedAt: Date
    var termName: String
    /// Next ~10 days of timetable items, sorted.
    var items: [Item]
    var average: Average?

    static let empty = WidgetSnapshot(generatedAt: .distantPast, termName: "", items: [], average: nil)

    static var fileURL: URL? {
        SharedConstants.sharedContainer?.appendingPathComponent(SharedConstants.snapshotFileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // MARK: Queries used by widgets (and the menu bar)

    func current(at date: Date) -> Item? {
        items.first { !$0.isDue && $0.start <= date && date < $0.end }
    }

    func next(after date: Date, classesOnly: Bool = false) -> Item? {
        items.first { $0.start > date && (!classesOnly || $0.isClass) }
    }

    func deadlines(after date: Date, limit: Int) -> [Item] {
        Array(items.filter { ($0.isAssessment || $0.isDue) && $0.end >= date }.prefix(limit))
    }

    func items(on day: Date, calendar: Calendar = .current) -> [Item] {
        items.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }
}
