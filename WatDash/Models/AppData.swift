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

/// Cards available on the Today dashboard. The user adds, removes and
/// reorders them; the list order is the layout order.
enum DashboardWidget: String, Codable, CaseIterable, Identifiable, Sendable {
    case nowNext, today, deadlines, overload, leverage, weekLoad, courseGrades, importHub, study, countdown, seatWatch, inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowNext: "Now & next"
        case .today: "Today"
        case .deadlines: "Upcoming deadlines"
        case .overload: "Overload tracker"
        case .leverage: "Highest-impact work"
        case .weekLoad: "Week at a glance"
        case .courseGrades: "Course grades"
        case .importHub: "Import"
        case .study: "Study"
        case .countdown: "Next exam countdown"
        case .seatWatch: "Seat watch"
        case .inbox: "Inbox"
        }
    }

    var subtitle: String {
        switch self {
        case .nowNext: "Current class and what's coming"
        case .today: "Everything on today's timetable"
        case .deadlines: "Due in the next two weeks"
        case .overload: "Projected average against your target"
        case .leverage: "Where study time moves your average most"
        case .weekLoad: "How heavy each day is"
        case .courseGrades: "Current grade in each course"
        case .importHub: "Pull in calendars, schedules and outlines"
        case .study: "Next assessment and its study pages"
        case .countdown: "Days until your next midterm or exam"
        case .seatWatch: "Open seats in sections you're waiting for"
        case .inbox: "Captured items waiting for a yes"
        }
    }

    var symbol: String {
        switch self {
        case .nowNext: "clock"
        case .today: "list.bullet.rectangle"
        case .deadlines: "flag"
        case .overload: "gauge.with.dots.needle.67percent"
        case .leverage: "arrow.up.right.circle"
        case .weekLoad: "chart.bar"
        case .courseGrades: "percent"
        case .importHub: "square.and.arrow.down"
        case .study: "book"
        case .countdown: "hourglass"
        case .seatWatch: "chair"
        case .inbox: "tray"
        }
    }

    /// Wide cards span two columns of the dashboard grid.
    var isWide: Bool {
        switch self {
        case .today, .weekLoad, .courseGrades, .importHub: true
        default: false
        }
    }

    static let defaultLayout: [DashboardWidget] = [.nowNext, .overload, .deadlines, .today, .leverage, .countdown, .weekLoad, .importHub]
}

struct AppSettings: Codable, Hashable, Sendable {
    // Term
    var termName: String = "Fall 2026"
    var termCode: String = "1269"
    var termStart: Date = Waterloo.calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)) ?? .now
    var termEnd: Date = Waterloo.calendar.date(from: DateComponents(year: 2026, month: 12, day: 23)) ?? .now
    var classesFolderPath: String = NSString(string: "~/Documents/University of Waterloo Classes").expandingTildeInPath

    // Grades
    var targetAverage: Double = 80
    var previousUnits: Double = 0
    var previousAverage: Double?
    /// How many points lower than coursework you tend to score on exams.
    /// Learned from your own history once there is any; this is the prior.
    var examGap: Double = 8
    var learnExamGap: Bool = true
    var roundCourseGrades: Bool = true

    // Dashboard
    var dashboard: [DashboardWidget] = DashboardWidget.defaultLayout

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
        targetAverage = value(.targetAverage, defaults.targetAverage)
        previousUnits = value(.previousUnits, defaults.previousUnits)
        previousAverage = try? c.decode(Double.self, forKey: .previousAverage)
        examGap = value(.examGap, defaults.examGap)
        learnExamGap = value(.learnExamGap, defaults.learnExamGap)
        roundCourseGrades = value(.roundCourseGrades, defaults.roundCourseGrades)
        // Unknown widget kinds from a newer build are dropped, not fatal.
        let rawDashboard = (try? c.decode([String].self, forKey: .dashboard)) ?? defaults.dashboard.map(\.rawValue)
        dashboard = rawDashboard.compactMap(DashboardWidget.init(rawValue:))
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
