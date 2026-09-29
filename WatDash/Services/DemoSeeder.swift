//
//  DemoSeeder.swift
//  WatDash
//

import Foundation

/// A realistic first-year CS Fall 2026 term, for trying the app before
/// importing anything (and for screenshots). Written to its own data file
/// under -WatDashDemo, or loaded on request from the Import screen.
enum DemoSeeder {
    static func sampleTerm(now: Date = .now) -> AppData {
        var data = AppData()
        let cal = Waterloo.calendar
        func day(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let source = DataSource(kind: .demo, name: "Sample term")
        data.sources = [source]

        // Courses and schemes.
        func component(_ name: String, _ weight: Double, drop: Int = 0, count: Int? = nil, exam: Bool = false) -> GradeComponent {
            GradeComponent(name: name, weight: weight, dropLowest: drop, expectedCount: count, isExam: exam)
        }
        var cs = Course(code: "CS 135", title: "Designing Functional Programs", colorIndex: 2)
        cs.scheme.components = [component("Assignments", 20, drop: 1, count: 9), component("Participation", 5, count: 1),
                                component("Midterm", 25, count: 1, exam: true), component("Final", 50, count: 1, exam: true)]
        cs.scheme.rules = [.mustPass(components: [cs.scheme.components[2].id, cs.scheme.components[3].id], threshold: 50)]
        var m135 = Course(code: "MATH 135", title: "Algebra for Honours Mathematics", colorIndex: 1, teachDontAnswer: true)
        m135.scheme.components = [component("Assignments", 10, count: 3), component("Quizzes", 15, drop: 1, count: 7),
                                  component("Midterm", 25, count: 1, exam: true), component("Final", 50, count: 1, exam: true)]
        var m137 = Course(code: "MATH 137", title: "Calculus 1 for Honours Mathematics", colorIndex: 0)
        m137.scheme.components = [component("Quizzes", 20, drop: 1, count: 10), component("Midterm", 30, count: 1, exam: true),
                                  component("Final", 50, count: 1, exam: true)]
        var econ = Course(code: "ECON 101", title: "Introduction to Microeconomics", colorIndex: 3)
        econ.scheme.components = [component("Online quizzes", 20, drop: 2, count: 10), component("Midterm", 35, count: 1, exam: true),
                                  component("Final", 45, count: 1, exam: true)]
        var engl = Course(code: "ENGL 109", title: "Introduction to Academic Writing", colorIndex: 4)
        engl.scheme.components = [component("Essays", 60, count: 3), component("Participation", 10, count: 1),
                                  component("Final portfolio", 30, count: 1)]
        data.courses = [cs, econ, engl, m135, m137]

        // Timetable.
        func meeting(_ code: String, _ label: String, _ kind: EventKind, _ weekdays: [Int], _ start: (Int, Int), _ end: (Int, Int), _ room: String) -> DashEvent {
            var first = day(9, 9)
            while !weekdays.contains(cal.component(.weekday, from: first)) { first = cal.date(byAdding: .day, value: 1, to: first)! }
            return DashEvent(
                id: "demo:\(code):\(label)", title: "\(code) \(label)", courseCode: code, kind: kind,
                start: cal.date(bySettingHour: start.0, minute: start.1, second: 0, of: first)!,
                end: cal.date(bySettingHour: end.0, minute: end.1, second: 0, of: first)!,
                location: room, recurrence: .weekly(on: weekdays, until: day(12, 8, 23, 59)),
                timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id
            )
        }
        data.events = [
            meeting("MATH 137", "LEC 004", .lecture, [2, 4, 6], (10, 30), (11, 20), "MC 2065"),
            meeting("MATH 137", "TUT 104", .tutorial, [2], (17, 30), (18, 50), "MC 1085"),
            meeting("MATH 135", "LEC 003", .lecture, [2, 4, 6], (12, 30), (13, 20), "MC 2066"),
            meeting("MATH 135", "TUT 102", .tutorial, [3], (15, 30), (16, 20), "DC 1350"),
            meeting("CS 135", "LEC 002", .lecture, [3, 5], (8, 30), (9, 50), "MC 2065"),
            meeting("CS 135", "TUT 105", .tutorial, [4], (14, 30), (15, 20), "MC 4045"),
            meeting("ECON 101", "LEC 001", .lecture, [3, 5], (11, 30), (12, 50), "AL 116"),
            meeting("ENGL 109", "LEC 012", .seminar, [2, 4], (14, 30), (15, 50), "HH 1104"),
            DashEvent(id: "demo:oh:cs135", title: "CS 135 office hours", courseCode: "CS 135", kind: .officeHours,
                      start: day(9, 15, 13), end: day(9, 15, 14, 30), location: "MC 4065",
                      recurrence: .weekly(on: [3], until: day(12, 8, 23, 59)), timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id),
            DashEvent(id: "demo:rw", title: "Reading week", kind: .holiday, start: day(10, 10), end: day(10, 19), isAllDay: true,
                      timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id, cancelsClasses: true),
            DashEvent(id: "demo:thanks", title: "Thanksgiving", kind: .holiday, start: day(10, 12), end: day(10, 13), isAllDay: true,
                      timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id, cancelsClasses: true),
            DashEvent(id: "demo:htn", title: "CS Club talk: compilers in 45 minutes", kind: .event,
                      start: day(10, 1, 18), end: day(10, 1, 19), location: "MC 4020", timeZoneID: Waterloo.timeZone.identifier,
                      sourceID: source.id),
        ]

        // Assessments with some marks already in.
        func assess(_ course: Course, _ title: String, _ kind: EventKind, _ component: Int, _ due: Date?, end: Date? = nil,
                    score: Double? = nil, coverage: String? = nil, location: String? = nil) -> Assessment {
            Assessment(courseCode: course.code, title: title, kind: kind, componentID: course.scheme.components[component].id,
                       due: due, end: end, coverage: coverage, location: location, score: score,
                       isDone: score != nil, sourceKey: "demo:\(course.code):\(title)", sourceID: source.id)
        }
        var list: [Assessment] = []
        // MATH 137 quizzes (Mondays 5:30 PM).
        let quizDays: [(Int, Int)] = [(9, 21), (9, 28), (10, 5), (10, 19), (11, 2), (11, 9), (11, 16), (11, 23), (11, 30), (12, 7)]
        let quizScores: [Double?] = [92, 85]
        for (index, date) in quizDays.enumerated() {
            let when = day(date.0, date.1, 17, 30)
            let score = index < quizScores.count ? quizScores[index] : nil
            list.append(assess(m137, "Quiz \(index + 1)", .quiz, 0, when, end: when.addingTimeInterval(50 * 60), score: score))
        }
        list.append(assess(m137, "Midterm", .test, 1, day(10, 26, 19), end: day(10, 26, 20, 50), coverage: "Chapters 1–2"))
        list.append(assess(m137, "Final exam", .exam, 2, nil))
        // MATH 135.
        list.append(assess(m135, "Assignment W1", .assignment, 0, day(9, 16, 16, 5), score: 88))
        list.append(assess(m135, "Assignment W2", .assignment, 0, day(9, 23, 16, 5), score: 81))
        list.append(assess(m135, "Assignment W3", .assignment, 0, day(9, 30, 16, 5), coverage: "3.2–3.5, 5.1–5.3"))
        list.append(assess(m135, "Quiz W4", .quiz, 1, day(10, 7, 16), end: day(10, 7, 17, 20), coverage: "3.6–4.3, 5.4–5.5"))
        list.append(assess(m135, "Midterm", .test, 2, day(10, 21, 19), end: day(10, 21, 20, 50), coverage: "Chapters 1–5"))
        for (index, date) in [(10, 28), (11, 4), (11, 11), (11, 18), (11, 25), (12, 2)].enumerated() {
            list.append(assess(m135, "Quiz W\(index + 5)", .quiz, 1, day(date.0, date.1, 16), end: day(date.0, date.1, 17, 20)))
        }
        list.append(assess(m135, "Final exam", .exam, 3, nil))
        // CS 135 assignments (Tuesdays 9 PM).
        let csScores: [Double?] = [100, 94, 97]
        for index in 0..<9 {
            let due = cal.date(byAdding: .day, value: 7 * index, to: day(9, 15, 21))!
            list.append(assess(cs, "A\(index)", .assignment, 0, due, score: index < csScores.count ? csScores[index] : nil))
        }
        list.append(assess(cs, "Midterm", .test, 2, day(10, 22, 19), end: day(10, 22, 20, 50)))
        list.append(assess(cs, "Final exam", .exam, 3, nil))
        // ECON 101.
        for index in 0..<10 {
            let due = cal.date(byAdding: .day, value: 7 * index, to: day(9, 18, 23, 59))!
            list.append(assess(econ, "Online quiz \(index + 1)", .quiz, 0, due, score: index < 2 ? [78, 90][index] : nil))
        }
        list.append(assess(econ, "Midterm", .test, 1, day(10, 29, 19), end: day(10, 29, 20, 30)))
        // ENGL 109.
        list.append(assess(engl, "Essay 1", .assignment, 0, day(10, 2, 23, 59)))
        list.append(assess(engl, "Essay 2", .assignment, 0, day(11, 6, 23, 59)))
        list.append(assess(engl, "Essay 3", .assignment, 0, day(11, 27, 23, 59)))
        data.assessments = list

        data.seatWatches = [SeatWatch(courseCode: "RUSS 101", section: "001", capacity: 40, enrolled: 40, lastChecked: now)]
        return data
    }
}
