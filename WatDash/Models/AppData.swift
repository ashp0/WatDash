//
//  AppData.swift
//  WatDash
//

import Foundation

/// The whole canonical store, as one Codable value. Small by design — a term
/// is a few hundred events — so a single JSON file is simpler, faster and far
/// easier to inspect than a database.
struct AppData: Codable, Sendable {
    var version: Int = 1
    var courses: [Course] = []
    var events: [DashEvent] = []
    var assessments: [Assessment] = []
    var sources: [DataSource] = []
    var seatWatches: [SeatWatch] = []
    var settings: AppSettings = AppSettings()

    init() {}

    // Tolerant decoding: a new field in a later version must never make an
    // older data file unreadable (and wipe someone's term).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        courses = (try? c.decode([Course].self, forKey: .courses)) ?? []
        events = (try? c.decode([DashEvent].self, forKey: .events)) ?? []
        assessments = (try? c.decode([Assessment].self, forKey: .assessments)) ?? []
        sources = (try? c.decode([DataSource].self, forKey: .sources)) ?? []
        seatWatches = (try? c.decode([SeatWatch].self, forKey: .seatWatches)) ?? []
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    // Term
    var termName: String = "Fall 2026"
    var termCode: String = "1269"
    var termStart: Date = Waterloo.calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)) ?? .now
    var termEnd: Date = Waterloo.calendar.date(from: DateComponents(year: 2026, month: 12, day: 23)) ?? .now
    var classesFolderPath: String = NSString(string: "~/Documents/University of Waterloo Classes").expandingTildeInPath
    /// iOS: the classes folder picked in Files, reopened through this
    /// security-scoped bookmark. The Mac app isn't sandboxed and uses the path.
    var classesFolderBookmark: Data?

    // Grades
    var targetAverage: Double = 80
    var previousUnits: Double = 0
    var previousAverage: Double?
    /// How many points lower than coursework you tend to score on exams.
    /// Learned from your own history once there is any; this is the prior.
    var examGap: Double = 8
    var learnExamGap: Bool = true
    var roundCourseGrades: Bool = true

    // Calendar sync
    var exportToAppleCalendar: Bool = false
    var exportClasses: Bool = true
    var exportDeadlines: Bool = true
    var exportedCalendarIDs: [String: String] = [:]

    // Notifications
    var notifyDeadlines: Bool = true
    var deadlineLeadHours: [Double] = [24, 2]
    var notifyClasses: Bool = false
    var classLeadMinutes: Double = 10

    // Behaviour
    var showMenuBarExtra: Bool = true
    var quickCaptureHotKey: Bool = true
    var smartCapture: Bool = true
    var feedRefreshMinutes: Double = 60

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        termName = value(.termName, defaults.termName)
        termCode = value(.termCode, defaults.termCode)
        termStart = value(.termStart, defaults.termStart)
        termEnd = value(.termEnd, defaults.termEnd)
        classesFolderPath = value(.classesFolderPath, defaults.classesFolderPath)
        classesFolderBookmark = try? c.decode(Data.self, forKey: .classesFolderBookmark)
        targetAverage = value(.targetAverage, defaults.targetAverage)
        previousUnits = value(.previousUnits, defaults.previousUnits)
        previousAverage = try? c.decode(Double.self, forKey: .previousAverage)
        examGap = value(.examGap, defaults.examGap)
        learnExamGap = value(.learnExamGap, defaults.learnExamGap)
        roundCourseGrades = value(.roundCourseGrades, defaults.roundCourseGrades)
        exportToAppleCalendar = value(.exportToAppleCalendar, defaults.exportToAppleCalendar)
        exportClasses = value(.exportClasses, defaults.exportClasses)
        exportDeadlines = value(.exportDeadlines, defaults.exportDeadlines)
        exportedCalendarIDs = value(.exportedCalendarIDs, defaults.exportedCalendarIDs)
        notifyDeadlines = value(.notifyDeadlines, defaults.notifyDeadlines)
        deadlineLeadHours = value(.deadlineLeadHours, defaults.deadlineLeadHours)
        notifyClasses = value(.notifyClasses, defaults.notifyClasses)
        classLeadMinutes = value(.classLeadMinutes, defaults.classLeadMinutes)
        showMenuBarExtra = value(.showMenuBarExtra, defaults.showMenuBarExtra)
        quickCaptureHotKey = value(.quickCaptureHotKey, defaults.quickCaptureHotKey)
        smartCapture = value(.smartCapture, defaults.smartCapture)
        feedRefreshMinutes = value(.feedRefreshMinutes, defaults.feedRefreshMinutes)
    }
}
