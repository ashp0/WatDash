//
//  Checks.swift
//  WatDash
//
//  Assertions on the pure logic — parsers, recurrence, the grade engine —
//  compiled natively by Tools/run_checks.sh. No app, no simulator, no clock:
//  every "now" is fixed so results are reproducible.
//

import Foundation

@main
struct Checks {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("✗ \(message())  (\(file):\(line))")
        }
    }

    static func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance
    }

    static let cal = Waterloo.calendar

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func main() {
        courseFolder()
        learnFolder()
        quest()
        outline()
        recurrence()
        grades()
        capture()
        ics()
        studyPrompt()
        focus()
        urgency()
        menuBar()
        timeGrid()
        realFolders()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Course folder CLAUDE.md

    static let math137 = """
    # MATH 137: Calculus 1 for Honours Mathematics (Fall 2026)

    ## Files

    - `MATH_137.pdf`: course notes, Fall 2026 edition, 263 pages.

    ## Assessments

    - Quizzes, 20%, best 9 of 10: Mondays at 5:30 PM in the tutorial slot, 50 minutes, closed book, no aids.
    - Midterm, 30%: Monday Oct 26, 7:00–8:50 PM. No quiz that day.
    - Final, 50%: date set by the Registrar.

    Last year's Quiz 2 layout (20 points, 35 minutes): short answer 2 × [2].

    ## Calendar

    | Assessment | Date | Notes sections |
    |---|---|---|
    | Quiz 1 | Mon Sep 21 | 0.1–1.1 |
    | Quiz 3 | Mon Oct 5 | 1.4–1.5, 2.1 |
    | Midterm | Mon Oct 26, 7:00 PM | Cumulative |
    | Final | TBA | Everything, including 4.10 |

    Reading week is Oct 10–18.

    ## Notes page map

    | § | Topic | Starts on page |
    |---|---|---|
    | 1.2 | Sequences and their limits | 37 (problems p. 49) |
    | 2.1 | Introduction to function limits | 74 |

    ## Study pages

    - **MATH 137 Quiz Prep**: https://claude.ai/artifact/Wzicy9hD3mTDZfd7pByCFb. Source `study/quiz-prep.src.html`, blue accent.
    """

    static let math135 = """
    # MATH 135: Algebra for Honours Mathematics (Fall 2026)

    ## How to help in this course

    - Teach the needed ideas with examples that differ from the assignment.

    ## Assessments and what they cover

    Assignments are due Wednesdays at 4:05 PM. Quizzes are Wednesdays, 4:00–5:20 PM.

    | Assessment | Date | Learning objectives | Notes sections |
    |---|---|---|---|
    | Assignment W3 | Wed Sep 30, 4:05 PM | 7–10 | 3.2–3.5, 5.1–5.3 |
    | Quiz W4 | Wed Oct 7, 4:00–5:20 PM | 11–17 | 3.6–4.3, 5.4–5.5 |
    | Quiz W5 | Wed Oct 28 | 18–22 | 6.1–6.5 |

    ## Notes page map

    | Chapter | Topic | Page | Sections |
    |---|---|---|---|
    | 3 | Proving statements | 39 | 3.1 p. 40, 3.2 p. 45, 3.3 p. 49 |
    | 6 | Greatest common divisor | 100 | 6.1–6.8, pp. 100–128 |
    """

    static func courseFolder() {
        let p = CourseFolderParser.parse(markdown: math137, fallbackYear: 2026)
        check(p.code == "MATH 137", "course code, got \(p.code ?? "nil")")
        check(p.title == "Calculus 1 for Honours Mathematics", "title, got \(p.title ?? "nil")")
        check(p.termName == "Fall 2026", "term")
        check(p.components.count == 3, "three components, got \(p.components.map(\.name))")
        if let quizzes = p.components.first {
            check(quizzes.name == "Quizzes" && quizzes.weight == 20 && quizzes.dropLowest == 1 && quizzes.expectedCount == 10,
                  "quizzes best 9 of 10, got \(quizzes)")
        }
        check(p.components.dropFirst().allSatisfy(\.isExam), "midterm and final are exams")
        check(p.rows.count == 4, "four calendar rows, got \(p.rows.count)")
        if let quiz1 = p.rows.first {
            check(quiz1.kind == .quiz, "quiz kind")
            check(quiz1.due == date(2026, 9, 21, 17, 30), "Quiz 1 at the default 5:30 PM, got \(String(describing: quiz1.due))")
            check(quiz1.end == date(2026, 9, 21, 18, 20), "Quiz 1 lasts 50 minutes, got \(String(describing: quiz1.end))")
            check(quiz1.coverage == "0.1–1.1", "coverage")
        }
        if let midterm = p.rows.first(where: { $0.title == "Midterm" }) {
            check(midterm.kind == .test && midterm.due == date(2026, 10, 26, 19), "midterm 7 PM")
        }
        check(p.rows.last?.due == nil && p.rows.last?.kind == .exam, "final is TBA")
        check(p.noClassRanges.first?.start == date(2026, 10, 10) && p.noClassRanges.first?.end == date(2026, 10, 18), "reading week range")
        check(p.pageMap.map(\.section) == ["1.2", "2.1"] && p.pageMap.first?.problemsPage == 49, "page map")
        check(p.studyLinks.first?.url == "https://claude.ai/artifact/Wzicy9hD3mTDZfd7pByCFb", "study link url, got \(p.studyLinks.first?.url ?? "nil")")
        check(p.notesFile == "MATH_137.pdf", "notes file")
        check(!p.teachDontAnswer, "137 has no teach-don't-answer rule")
        check(p.accentIndex == 0, "blue accent maps to palette blue")

        let q = CourseFolderParser.parse(markdown: math135, fallbackYear: 2026)
        check(q.teachDontAnswer, "135 teach-don't-answer rule detected")
        check(q.rows.first?.kind == .assignment && q.rows.first?.due == date(2026, 9, 30, 16, 5), "Assignment W3 due 4:05 PM")
        check(q.rows[1].due == date(2026, 10, 7, 16) && q.rows[1].end == date(2026, 10, 7, 17, 20), "Quiz W4 4:00–5:20 PM")
        check(q.rows[2].due == date(2026, 10, 28, 16), "Quiz W5 takes the default quiz time")
        check(q.rows[1].coverage == "3.6–4.3, 5.4–5.5", "coverage uses the notes-sections column")
        check(q.pageMap.map(\.section) == ["3.1", "3.2", "3.3", "6"], "chapter page map, got \(q.pageMap.map(\.section))")
    }

    // MARK: - Marks, rooms and office hours from LEARN

    static let cs145 = """
    # CS 145: Designing Functional Programs (Advanced Version) (Fall 2026)

    ## Assessments

    - Assignments, 30%, best 11 of 11: due 10:00 PM on Marmoset.
    - Midterm 1, 10%: Thu Oct 8, 7:00–8:50 PM.
    - Midterm 2, 20%: Mon Nov 9, 7:00–8:50 PM.
    - Final exam, 40%: date set by the Registrar.

    ## Calendar

    | Assessment | Date | Covers | Room | Mark |
    |---|---|---|---|---|
    | A1 | Wed Sep 16, 10:00 PM | Counting steps | | 100% |
    | A2 | Wed Sep 23, 10:00 PM | Functions | | 91.67% |
    | A3 | Wed Sep 30, 10:00 PM | Trees | | submitted |
    | Midterm 1 | Thu Oct 8, 7:00–8:50 PM | A0–A3 | MC 1085, seat E-14 | |
    | Midterm 2 | Mon Nov 9, 7:00–8:50 PM | A0–A7 | TBA | 15 / 19 (78.9%) |

    ## Office hours

    - Tue 11:30am–12:30pm MC 5473, Troy Vasiga, weekly until Dec 8
    - Wed 2:30-4pm MC 4065, ISA consulting, weekly until Dec 8
    - whenever, by appointment
    """

    static func learnFolder() {
        let p = CourseFolderParser.parse(markdown: cs145, fallbackYear: 2026)
        check(p.code == "CS 145", "code, got \(p.code ?? "nil")")
        check(p.rows.count == 5, "five rows, got \(p.rows.count)")
        guard p.rows.count == 5 else { return }
        check(p.rows[0].score == 100 && p.rows[0].outOf == 100 && p.rows[0].isDone, "percent mark, got \(String(describing: p.rows[0].score))")
        check(near(p.rows[1].score, 91.67) && p.rows[1].outOf == 100, "decimal percent mark")
        check(p.rows[2].score == nil && p.rows[2].isDone, "submitted but unmarked is done")
        check(p.rows[3].score == nil && !p.rows[3].isDone && p.rows[3].location == "MC 1085, seat E-14", "room column, got \(p.rows[3].location ?? "nil")")
        check(p.rows[4].score == 15 && p.rows[4].outOf == 19 && p.rows[4].location == nil, "fraction mark wins over the percent; TBA room dropped")
        check(p.rows[3].coverage == "A0–A3", "covers column still read")
        check(CourseFolderParser.parseMark("—") == nil && CourseFolderParser.parseMark("") == nil, "blank marks are nil")

        // Midterm 2 belongs to "Midterm 2", not the first component mentioning a midterm.
        let scheme = GradeScheme(components: p.components)
        check(scheme.guessComponent(kind: .test, title: "Midterm 2")?.name == "Midterm 2", "exact component name wins")
        check(scheme.guessComponent(kind: .test, title: "Midterm 1")?.name == "Midterm 1", "Midterm 1 maps to itself")
        check(scheme.guessComponent(kind: .assignment, title: "A7")?.name == "Assignments", "A7 → Assignments by keyword")
        let engl = GradeScheme(components: [GradeComponent(name: "Skills challenges", weight: 6), GradeComponent(name: "Major assignments", weight: 75)])
        check(engl.guessComponent(kind: .deadline, title: "Skills challenge 2: Proposal and pitch")?.name == "Skills challenges", "singular prefix of a plural component")

        check(p.officeHours.count == 3, "three office-hour lines, got \(p.officeHours.count)")
        let termStart = date(2026, 9, 8)
        let hours = CourseFolderParser.officeHourEvents(p.officeHours, code: "CS 145", termStart: termStart, sourceID: nil)
        check(hours.count == 2, "the dateless line is skipped, got \(hours.count)")
        if let troy = hours.first {
            check(troy.kind == .officeHours && troy.courseCode == "CS 145" && troy.location == "MC 5473", "OH kind, course and room")
            check(troy.start == date(2026, 9, 8, 11, 30) && troy.end == date(2026, 9, 8, 12, 30), "first Tuesday of term, got \(troy.start)")
            check(troy.recurrence?.weekdays == [3] && troy.recurrence?.until == date(2026, 12, 8, 23, 59), "weekly on Tuesdays until Dec 8")
            check(troy.title.contains("Troy Vasiga"), "who, in the title: \(troy.title)")
        }
        let again = CourseFolderParser.officeHourEvents(p.officeHours, code: "CS 145", termStart: termStart, sourceID: nil)
        check(hours.map(\.id) == again.map(\.id) && Set(hours.map(\.id)).count == 2, "ids are stable and distinct")

        // A timetable TST slot is dropped where the course's own midterm sits;
        // office hours stop for reading week like classes do.
        let midterm = Assessment(courseCode: "CS 145", title: "Midterm 1", kind: .test, due: date(2026, 10, 8, 19), end: date(2026, 10, 8, 20, 50))
        let slot = DashEvent(id: "flow:tst", title: "CS145 - TST 201", courseCode: "CS 145", kind: .test,
                             start: date(2026, 10, 8, 19), end: date(2026, 10, 8, 20, 50))
        let otherSlot = DashEvent(id: "flow:tst2", title: "CS145 - TST 201", courseCode: "CS 145", kind: .test,
                                  start: date(2026, 11, 9, 19), end: date(2026, 11, 9, 20, 50))
        let readingWeek = DashEvent(id: "noclass", title: "Reading week", kind: .holiday, start: date(2026, 10, 10), end: date(2026, 10, 19),
                                    isAllDay: true, cancelsClasses: true)
        let window = DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 30))
        let agenda = RecurrenceExpander.agenda(events: [slot, otherSlot, readingWeek] + hours, assessments: [midterm], in: window)
        check(agenda.filter { $0.kind == .test }.map(\.title) == ["Midterm 1", "CS145 - TST 201"], "covered slot hidden, uncovered kept, got \(agenda.filter { $0.kind == .test }.map(\.title))")
        let quiz = Assessment(courseCode: "MATH 137", title: "Quiz 3", kind: .quiz, due: date(2026, 10, 5, 17, 30), end: date(2026, 10, 5, 18, 20))
        let tutorial = DashEvent(id: "flow:tut", title: "MATH137 - TUT 107", courseCode: "MATH 137", kind: .tutorial,
                                 start: date(2026, 9, 28, 17, 30), end: date(2026, 9, 28, 18, 50),
                                 recurrence: .weekly(on: [2], until: date(2026, 10, 6)))
        let tutorials = RecurrenceExpander.agenda(events: [tutorial], assessments: [quiz], in: window)
            .filter { $0.kind == .tutorial }.map { cal.component(.day, from: $0.start) }
        check(tutorials == [], "the Oct 5 tutorial gives way to Quiz 3, got \(tutorials)")
        let septemberTutorial = RecurrenceExpander.agenda(events: [tutorial], assessments: [quiz], in: DateInterval(start: date(2026, 9, 28), end: date(2026, 9, 29)))
        check(septemberTutorial.count == 1, "a tutorial without a quiz stays")

        let troyDays = agenda.filter { $0.kind == .officeHours && $0.location == "MC 5473" }.map { cal.component(.day, from: $0.start) }
        check(!troyDays.contains(13), "no office hours on the reading-week Tuesday, got \(troyDays)")
        check(troyDays.contains(6) && troyDays.contains(20), "office hours either side of reading week")
    }

    // MARK: - Quest paste

    static func quest() {
        let paste = """
        MATH 137 - Calculus 1 for Honours Mathematics
        Status\tUnits\tGrading\tGrade\tDeadlines
        Enrolled\t0.50\tNumeric Grading Basis\t\tAcademic Calendar Deadlines
        Class Nbr\tSection\tComponent\tDays & Times\tRoom\tInstructor\tStart/End Date
        4321\t005\tLEC\tMWF 10:30AM - 11:20AM\tSTC 0010\tRobert Garbary\t09/09/2026 - 12/08/2026
        4400\t104\tTUT\tM 5:30PM - 6:50PM\tMC 1085\tTBA\t09/09/2026 - 12/08/2026
        CS 135 - Designing Functional Programs
        5120\t002\tLEC\tTTh 8:30AM - 9:50AM\tMC 2065\tSomeone Prof\t09/09/2026 - 12/08/2026
        """
        let meetings = QuestScheduleParser.parse(paste, year: 2026)
        check(meetings.count == 3, "three meetings, got \(meetings.count)")
        guard meetings.count == 3 else { return }
        check(meetings[0].courseCode == "MATH 137" && meetings[0].weekdays == [2, 4, 6], "MWF")
        check(meetings[0].startMinutes == 630 && meetings[0].endMinutes == 680, "10:30–11:20")
        check(meetings[0].location == "STC 0010" && meetings[0].section == "005" && meetings[0].component == "LEC", "room/section/component")
        check(meetings[1].weekdays == [2] && meetings[1].startMinutes == 17 * 60 + 30, "tutorial Monday 5:30 PM")
        check(meetings[1].instructor == nil, "TBA instructor dropped")
        check(meetings[2].courseCode == "CS 135" && meetings[2].weekdays == [3, 5], "TTh")

        let event = meetings[0].event(sourceID: nil, fallbackStart: date(2026, 9, 8), fallbackEnd: date(2026, 12, 8))
        check(event?.start == date(2026, 9, 9, 10, 30), "first MWF meeting on or after Sep 9 is Wed Sep 9")
        check(event?.recurrence?.weekdays == [2, 4, 6], "weekly MWF rule")
    }

    // MARK: - Outline

    static func outline() {
        let html = """
        <html><head><title>Fall 2026: Calculus 1 for Honours Mathematics</title></head><body>
        <figure class="schedule-info"><table><tbody>
        <tr><th rowspan="1">MATH 137 <span class="section">005 <span class="class-type">[LEC]</span></span></th>
        <td class="meet-days"><div class="days-visual" title="Monday , Wednesday , Friday" aria-hidden="true"></div>
        <div class="date-range"><span>Sep 9 - Dec 8</span></div></td>
        <td>10:30AM - 11:20AM</td><td>STC 0010</td>
        <td rowspan="1"><div class="instructor-info"><span>Robert Garbary</span></div></td></tr>
        <tr><th rowspan="1">MATH 137 <span class="section">201 <span class="class-type">[TST]</span></span></th>
        <td class="meet-days"><div class="days-visual" title="Monday" aria-hidden="true"></div>
        <div class="date-range"><span>Oct 26</span></div></td>
        <td>07:00PM - 08:50PM</td><td></td></tr>
        </tbody></table></figure>
        <h2 id="assessments_amp_activities" class="header">Assessments &amp; Activities</h2>
        <div class="multitable-container"><table class="multitable"><thead><tr><th>Component</th></tr></thead><tbody>
        <tr><td> Quizzes </td><td> Mondays at 5:30 pm </td><td> In-person </td><td> 20 </td></tr>
        <tr><td> Midterm Exam </td><td> Monday, October 26 at 7:00 pm </td><td> In-person </td><td> 30 </td></tr>
        <tr><td> Final Exam </td><td> TBA </td><td> In-person </td><td> 50 </td></tr>
        </tbody></table></div></body></html>
        """
        let parsed = OutlineParser.parse(html: html, year: 2026)
        check(parsed.courseCode == "MATH 137", "outline course code")
        check(parsed.courseTitle == "Calculus 1 for Honours Mathematics", "outline title, got \(parsed.courseTitle ?? "nil")")
        check(parsed.meetings.count == 2, "two sections, got \(parsed.meetings.count)")
        check(parsed.meetings.first?.weekdays == [2, 4, 6] && parsed.meetings.first?.startMinutes == 630, "LEC 005 MWF 10:30")
        check(parsed.meetings.first?.instructor == "Robert Garbary", "instructor")
        check(parsed.meetings.last?.firstDay == date(2026, 10, 26) && parsed.meetings.last?.lastDay == date(2026, 10, 26), "TST single day")
        let testEvent = parsed.meetings.last?.event(sourceID: nil, fallbackStart: date(2026, 9, 8), fallbackEnd: date(2026, 12, 8))
        check(testEvent?.recurrence == nil && testEvent?.kind == .test, "single-day TST is a one-off test")
        let scheme = OutlineParser.scheme(from: parsed.assessments)
        check(scheme.components.map(\.weight) == [20, 30, 50], "outline weights, got \(scheme.components.map(\.weight))")
        check(scheme.components[1].isExam && !scheme.components[0].isExam, "exam flags")
    }

    // MARK: - Recurrence

    static func recurrence() {
        let lecture = DashEvent(
            id: "lec", title: "MATH 137 LEC 005", courseCode: "MATH 137", kind: .lecture,
            start: date(2026, 9, 9, 10, 30), end: date(2026, 9, 9, 11, 20),
            recurrence: .weekly(on: [2, 4, 6], until: date(2026, 12, 8, 23, 59)),
            exceptionDates: [date(2026, 9, 11, 10, 30)],
            timeZoneID: "America/Toronto"
        )
        let term = DateInterval(start: date(2026, 9, 1), end: date(2026, 12, 31))
        let all = RecurrenceExpander.occurrences(of: lecture, in: term)
        // Sep 9 – Dec 8 MWF: 39 meetings, minus the one exception.
        check(all.count == 38, "MWF meetings Sep 9–Dec 8 minus one exception, got \(all.count)")
        check(!all.contains { $0.start == date(2026, 9, 11, 10, 30) }, "exception removed")
        check(all.contains { $0.start == date(2026, 11, 2, 10, 30) }, "10:30 local after the Nov 1 DST change")
        check(all.last?.start == date(2026, 12, 7, 10, 30), "last meeting Mon Dec 7, got \(String(describing: all.last?.start))")

        let readingWeek = DashEvent(id: "rw", title: "Reading week", kind: .holiday,
                                    start: date(2026, 10, 10), end: date(2026, 10, 19), isAllDay: true,
                                    timeZoneID: "America/Toronto", cancelsClasses: true)
        let quiz = Assessment(courseCode: "MATH 137", title: "Quiz 4", kind: .quiz, due: date(2026, 10, 19, 17, 30))
        let deadline = Assessment(courseCode: "MATH 135", title: "A5", kind: .assignment, due: date(2026, 10, 14, 16, 5))
        let items = RecurrenceExpander.agenda(events: [lecture, readingWeek], assessments: [quiz, deadline], in: term)
        let lectures = items.filter { $0.kind == .lecture }
        check(lectures.count == 35, "reading week cancels 3 lectures (Oct 12, 14, 16), got \(lectures.count)")
        check(items.contains { $0.title == "A5" }, "deadlines survive reading week")
        check(items.contains { $0.title == "Quiz 4" && $0.end == date(2026, 10, 19, 18, 20) }, "quiz gets a 50-minute block")

        let counted = DashEvent(id: "c", title: "OH", kind: .officeHours, start: date(2026, 9, 15, 14), end: date(2026, 9, 15, 15),
                                recurrence: Recurrence(frequency: .weekly, interval: 1, count: 3, until: nil, weekdays: []))
        check(RecurrenceExpander.occurrences(of: counted, in: term).count == 3, "COUNT=3")
    }

    // MARK: - Grades

    static func grades() {
        let quizzes = UUID(), midterm = UUID(), final = UUID()
        func item(_ p: Double?, whatIf: Double? = nil) -> GradeEngine.ItemInput {
            GradeEngine.ItemInput(id: UUID(), title: "x", due: nil, percent: p, whatIf: whatIf)
        }
        var course = GradeEngine.CourseInput(code: "MATH 137", units: 0.5, components: [
            .init(id: quizzes, name: "Quizzes", weight: 20, dropLowest: 1, expectedCount: 10, isExam: false,
                  items: [item(90), item(80)]),
            .init(id: midterm, name: "Midterm", weight: 30, dropLowest: 0, expectedCount: 1, isExam: true, items: []),
            .init(id: final, name: "Final", weight: 50, dropLowest: 0, expectedCount: 1, isExam: true, items: []),
        ], rules: [])
        let params = GradeEngine.Parameters(target: 80, examGap: 8)

        var r = GradeEngine.evaluate(course, parameters: params)
        check(near(r.current, 85), "current = mean of two quizzes, got \(String(describing: r.current))")
        // Floor: two quiz marks over 9 kept slots, ×20%.
        check(near(r.floor, (90 + 80) / 9.0 * 0.2), "floor, got \(r.floor)")
        // Ceiling: eight 100s plus the 90; the 80 is the dropped quiz.
        check(near(r.ceiling, (800 + 90) / 9.0 * 0.2 + 80), "ceiling, got \(r.ceiling)")
        // Projection: unwritten quizzes at 85 (the 80 drops), exams at 85 − 8 = 77.
        check(near(r.projected, (90 + 8 * 85) / 9.0 * 0.2 + 77 * 0.8), "projected with exam gap, got \(String(describing: r.projected))")
        if case let .needs(x) = r.requirement {
            // Solve 0.2·(170 + 7x)/9 + 0.8x = 80.
            let expected = (80 - 0.2 * 170 / 9) / (0.2 * 7 / 9 + 0.8)
            check(abs(x - expected) < 0.01, "required uniform score \(x) vs \(expected)")
        } else {
            check(false, "expected a requirement, got \(r.requirement)")
        }

        // Final replaces midterm when better.
        course.components[1].items = [item(60)]
        course.components[2].items = [item(90)]
        course.rules = [.replaceIfBetter(target: midterm, with: final)]
        r = GradeEngine.evaluate(course, parameters: params)
        check(near(r.floor, (90 + 80) / 9.0 * 0.2 + 90 * 0.3 + 90 * 0.5), "replacement lifts the midterm to 90")

        // Must pass exams: exam average 40 caps the grade at 40.
        course.rules = [.mustPass(components: [midterm, final], threshold: 50)]
        course.components[1].items = [item(40)]
        course.components[2].items = [item(40)]
        course.components[0].items = (0..<10).map { _ in item(100) }
        r = GradeEngine.evaluate(course, parameters: params)
        check(near(r.floor, 40), "exam-pass rule caps at the exam average, got \(r.floor)")
        check(r.requirement == .noRemainingWork, "everything marked")

        // Drop lowest only once there are more marks than kept slots.
        let dropCourse = GradeEngine.CourseInput(code: "X", units: 0.5, components: [
            .init(id: UUID(), name: "Q", weight: 100, dropLowest: 1, expectedCount: 3, isExam: false,
                  items: [item(100), item(50), item(0)]),
        ], rules: [])
        check(near(GradeEngine.evaluate(dropCourse, parameters: params).floor, 75), "best 2 of 3")

        // Term: unit-weighted, rounded course grades.
        let a = GradeEngine.CourseInput(code: "A", units: 0.5, components: [
            .init(id: UUID(), name: "All", weight: 100, dropLowest: 0, expectedCount: 1, isExam: false, items: [item(79.5)])], rules: [])
        let b = GradeEngine.CourseInput(code: "B", units: 0.5, components: [
            .init(id: UUID(), name: "All", weight: 100, dropLowest: 0, expectedCount: 1, isExam: false, items: [item(80.4)])], rules: [])
        let term = GradeEngine.evaluateTerm([a, b], parameters: params)
        check(near(term.projected, 80), "79.5 and 80.4 round to 80 and 80, got \(String(describing: term.projected))")
        check(term.requiredOnRemaining == .secured || term.requiredOnRemaining == .noRemainingWork, "nothing left to do")

        let cumulative = GradeEngine.evaluateTerm([a], parameters: params, previousUnits: 2.5, previousAverage: 86)
        check(near(cumulative.cumulativeProjected, (86 * 2.5 + 80 * 0.5) / 3), "cumulative blends previous terms")

        let leverage = GradeEngine.leverage([course], totalUnits: 2.5)
        check(leverage.isEmpty, "all graded → no leverage items")
    }

    // MARK: - Quick capture

    static func capture() {
        let now = date(2026, 9, 29, 9, 0)  // Tuesday morning
        let known = ["CS 135", "MATH 135", "MATH 137"]

        var r = QuickCaptureParser.parse("CS 135 OH Tue 2-3pm MC 4065 weekly until Dec 4", now: now, knownCourses: known)
        check(r.courseCode == "CS 135" && r.kind == .officeHours, "OH kind, got \(r.kind)")
        check(r.start == date(2026, 9, 29, 14) && r.end == date(2026, 9, 29, 15), "today 2–3 PM, got \(String(describing: r.start))")
        check(r.location == "MC 4065", "building room, got \(r.location ?? "nil")")
        check(r.recurrence?.weekdays == [3] && r.recurrence?.until == date(2026, 12, 4, 23, 59), "weekly until Dec 4")

        r = QuickCaptureParser.parse("math137 quiz 4 oct 19 5:30pm", now: now, knownCourses: known)
        check(r.courseCode == "MATH 137" && r.kind == .quiz && r.title == "Quiz 4", "quiz 4, got \(r.title)")
        check(r.start == date(2026, 10, 19, 17, 30), "Oct 19 5:30 PM")

        r = QuickCaptureParser.parse("A4 due fri 11:59pm", now: now, knownCourses: known)
        check(r.kind == .assignment && r.title == "Assignment 4", "A4, got \(r.kind) \(r.title)")
        check(r.start == date(2026, 10, 2, 23, 59) && r.start == r.end, "Friday 11:59 PM point deadline")

        r = QuickCaptureParser.parse("hack the north info session tomorrow 6pm @ SLC Great Hall", now: now, knownCourses: known)
        check(r.kind == .event && r.start == date(2026, 9, 30, 18), "tomorrow 6 PM event, got \(String(describing: r.start))")
        check(r.title.lowercased().contains("hack the north"), "title kept, got \(r.title)")

        r = QuickCaptureParser.parse("MATH 135 midterm 2026-10-21 7-8:50pm", now: now, knownCourses: known)
        check(r.kind == .test && r.start == date(2026, 10, 21, 19) && r.end == date(2026, 10, 21, 20, 50), "ISO date + range")

        r = QuickCaptureParser.parse("tue 9am study group", now: now, knownCourses: known)
        check(r.start == date(2026, 10, 6, 9), "Tuesday 9 AM already passed today → next week, got \(String(describing: r.start))")
    }

    // MARK: - ICS

    static func ics() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:abc
        SUMMARY:CS 135 LEC 002
        LOCATION:MC 2065
        DTSTART;TZID=America/Toronto:20260910T083000
        DTEND;TZID=America/Toronto:20260910T095000
        RRULE:FREQ=WEEKLY;UNTIL=20261208T235900;BYDAY=TU,TH
        EXDATE;TZID=America/Toronto:20261013T083000
        END:VEVENT
        END:VCALENDAR
        """
        guard let events = try? ICSParser.parse(text) else { check(false, "ics parse"); return }
        check(events.count == 1 && events[0].recurrence?.weekdays == [3, 5], "TU,TH")
        let imported = ICSImport.events(from: events, sourceID: nil, knownCourses: ["CS 135"])
        check(imported.first?.courseCode == "CS 135" && imported.first?.kind == .lecture, "course + kind from summary")
        let count = imported.first.map { RecurrenceExpander.occurrences(of: $0, in: DateInterval(start: date(2026, 9, 1), end: date(2027, 1, 1))).count }
        check(count == 25, "Sep 10–Dec 8 TuTh is 26 meetings minus one EXDATE, got \(String(describing: count))")
    }

    // MARK: - Study prompt

    static func studyPrompt() {
        let map = [
            NotesSection(section: "1.3", title: "Arithmetic rules for limits", page: 51, problemsPage: 55),
            NotesSection(section: "1.4", title: "Squeeze Theorem", page: 59, problemsPage: 61),
            NotesSection(section: "1.5", title: "Recursive sequences", page: 63),
            NotesSection(section: "2.1", title: "Introduction to function limits", page: 74),
            NotesSection(section: "2.2", title: "Sequential characterization of limits", page: 80),
            NotesSection(section: "2.10", title: "Intermediate Value Theorem", page: 126),
        ]
        let covered = StudyPrompt.sections(for: "1.4–1.5, 2.1", in: map)
        check(covered.map(\.section) == ["1.4", "1.5", "2.1"], "coverage expands ranges, got \(covered.map(\.section))")
        check(StudyPrompt.sections(for: "2.2–2.10", in: map).map(\.section) == ["2.2", "2.10"], "2.10 sorts after 2.2")

        var course = Course(code: "MATH 137", title: "Calculus 1", folderPath: "/tmp/Math137")
        course.pageMap = map
        course.notesFile = "MATH_137.pdf"
        course.studyLinks = [StudyLink(title: "MATH 137 Quiz Prep", url: "https://claude.ai/artifact/abc")]
        let quiz = Assessment(courseCode: "MATH 137", title: "Quiz 3", kind: .quiz, due: date(2026, 10, 5, 17, 30), coverage: "1.4–1.5, 2.1")
        let prompt = StudyPrompt(course: course, sections: covered, assessment: quiz, classesRoot: "/Users/x/UW Classes")
        let ranges = prompt.pageRanges()
        check(ranges.map(\.1) == [59...62, 63...73, 74...79], "page ranges end before the next section, got \(ranges.map(\.1))")
        let text = prompt.text
        check(text.hasPrefix("Use the quiz-prep skill to build a study page for MATH 137 Quiz 3"), "prompt names the skill and assessment")
        check(text.contains("Math137/CLAUDE.md") && text.contains("Math137/MATH_137.pdf"), "prompt points at the course files")
        check(text.contains("§1.4 Squeeze Theorem (pp. 59–62, problems p. 61)"), "section line with pages")
        check(text.contains("https://claude.ai/artifact/abc"), "extends the existing page")
        check(!text.contains("strict rule"), "no teach-don't-answer rule for 137")
        course.teachDontAnswer = true
        check(StudyPrompt(course: course, sections: covered, assessment: quiz, classesRoot: "/x").text.contains("strict rule"), "135-style rule included")
        check(prompt.terminalCommand.hasPrefix("cd \"/Users/x/UW Classes\" && claude '"), "terminal command quotes the folder")
    }

    // MARK: - Focus

    static func focus() {
        let now = date(2026, 9, 29, 12)
        func item(_ title: String, _ kind: EventKind, _ start: Date, end: Date? = nil, done: Bool = false) -> AgendaItem {
            AgendaItem(id: title, origin: .assessment(UUID()), title: title, courseCode: "CS 135", kind: kind,
                       start: start, end: end ?? start, isAllDay: false, isDone: done)
        }
        let agenda = [
            item("Stale", .assignment, date(2026, 9, 27, 9)),
            item("Late", .assignment, date(2026, 9, 28, 23, 59)),
            item("Written quiz", .quiz, date(2026, 9, 29, 9), end: date(2026, 9, 29, 10)),
            item("Quiz now", .quiz, date(2026, 9, 29, 11, 30), end: date(2026, 9, 29, 12, 30)),
            item("Due tonight", .assignment, date(2026, 9, 29, 23, 59)),
            item("Submitted", .assignment, date(2026, 9, 29, 16), done: true),
            item("Due in 40h", .assignment, date(2026, 10, 1, 4)),
            item("Assignment in 3d", .assignment, date(2026, 10, 2, 12)),
            item("Midterm in 5d", .test, date(2026, 10, 4, 19), end: date(2026, 10, 4, 21)),
            item("Final in 9d", .exam, date(2026, 10, 8, 9), end: date(2026, 10, 8, 11)),
        ]
        let entries = Focus.entries(from: agenda, now: now)
        check(entries.map(\.item.title) == ["Late", "Quiz now", "Due tonight", "Due in 40h", "Midterm in 5d"],
              "focus keeps late, 48-hour and exam-week work in urgency order, got \(entries.map(\.item.title))")
        check(entries.map(\.urgency) == [.overdue, .within24h, .within24h, .within48h, .examThisWeek], "focus urgencies")
        check(Focus.window(around: now).contains(date(2026, 9, 27, 13)) && Focus.window(around: now).contains(date(2026, 10, 6, 11)),
              "focus window spans the late grace and the exam week")
    }

    // MARK: - Urgency

    static func urgency() {
        let now = date(2026, 9, 29, 12)
        func work(_ title: String, _ kind: EventKind, _ start: Date, end: Date? = nil, done: Bool = false) -> AgendaItem {
            AgendaItem(id: title, origin: .assessment(UUID()), title: title, courseCode: "CS 145", kind: kind,
                       start: start, end: end ?? start, isAllDay: false, isDone: done)
        }
        let quiz = work("Quiz tomorrow", .quiz, date(2026, 9, 30, 10), end: date(2026, 9, 30, 10, 50))
        let midterm = work("Midterm in 3 days", .test, date(2026, 10, 2, 12), end: date(2026, 10, 2, 14))
        let assignment = work("Due in 2 hours", .assignment, date(2026, 9, 29, 14))
        func weight(_ item: AgendaItem, _ value: Double) -> (UUID, Double)? {
            if case let .assessment(id) = item.origin { return (id, value) }
            return nil
        }
        let weights = Dictionary(uniqueKeysWithValues: [weight(quiz, 2), weight(midterm, 30), weight(assignment, 3)].compactMap { $0 })
        let ranked = Urgency.ranked([quiz, midterm, assignment], weights: weights, now: now)
        check(ranked.map(\.item.title) == ["Due in 2 hours", "Midterm in 3 days", "Quiz tomorrow"],
              "deadline proximity, then weight × effort, got \(ranked.map(\.item.title))")
        check(ranked[1].score >= Urgency.critical && ranked[2].score < Urgency.critical,
              "a 30% midterm three days out is pressing; a 2% quiz tomorrow isn't, got \(ranked.map(\.score))")

        let heavy = work("Worth 20%", .quiz, date(2026, 9, 30, 12)), light = work("Worth 2%", .quiz, date(2026, 9, 30, 12))
        let byWeight = Dictionary(uniqueKeysWithValues: [weight(heavy, 20), weight(light, 2)].compactMap { $0 })
        check(Urgency.ranked([light, heavy], weights: byWeight, now: now).first?.item.title == "Worth 20%", "same time: the heavier item first")

        let late = work("Late", .assignment, date(2026, 9, 29, 9))
        let stale = work("Stale", .assignment, date(2026, 9, 26, 9))
        let written = work("Written quiz", .quiz, date(2026, 9, 29, 9), end: date(2026, 9, 29, 10))
        let writing = work("Quiz now", .quiz, date(2026, 9, 29, 11, 30), end: date(2026, 9, 29, 12, 30))
        let done = work("Done", .assignment, date(2026, 9, 29, 13), done: true)
        let lateRanked = Urgency.ranked([late, stale, written, writing, done, quiz], weights: [:], now: now)
        check(lateRanked.map(\.item.title) == ["Late", "Quiz tomorrow"],
              "late work leads; stale, written, in-progress and done items drop out, got \(lateRanked.map(\.item.title))")
        check(lateRanked.first?.isOverdue == true && (lateRanked.first?.score ?? 0) >= Urgency.critical, "late work is always pressing")
    }

    // MARK: - Menu bar

    static func menuBar() {
        // Tuesday Sep 29, the real timetable: CS 145 10:00, ECON 101 11:30, ENGL 119 2:30.
        func lecture(_ code: String, _ start: Date, _ end: Date) -> AgendaItem {
            AgendaItem(id: "\(code)@\(start)", origin: .event(code), title: "\(code.replacingOccurrences(of: " ", with: "")) - LEC 001",
                       courseCode: code, kind: .lecture, start: start, end: end, isAllDay: false)
        }
        func work(_ code: String, _ title: String, _ kind: EventKind, _ start: Date, end: Date? = nil, done: Bool = false) -> AgendaItem {
            AgendaItem(id: "\(code) \(title)", origin: .assessment(UUID()), title: title, courseCode: code, kind: kind,
                       start: start, end: end ?? start, isAllDay: false, isDone: done)
        }
        let cs = lecture("CS 145", date(2026, 9, 29, 10), date(2026, 9, 29, 11, 20))
        let econ = lecture("ECON 101", date(2026, 9, 29, 11, 30), date(2026, 9, 29, 12, 50))
        let engl = lecture("ENGL 119", date(2026, 9, 29, 14, 30), date(2026, 9, 29, 15, 50))
        let a4 = work("CS 145", "A4", .assignment, date(2026, 9, 30, 22))
        let midterm = work("CS 145", "Midterm 1", .test, date(2026, 10, 8, 19), end: date(2026, 10, 8, 20, 50))
        var weights: [UUID: Double] = [:]
        for (item, weight) in [(a4, 30.0 / 11), (midterm, 10)] { if case let .assessment(id) = item.origin { weights[id] = weight } }
        let agenda = [cs, econ, engl, a4, midterm]
        func status(_ h: Int, _ m: Int, day: Int = 29, _ items: [AgendaItem]? = nil) -> MenuBarStatus.Status {
            MenuBarStatus.resolve(items ?? agenda, weights: weights, now: date(2026, 9, day, h, m), calendar: cal)
        }

        var s = status(14, 45)
        check(s.reason == .inClass && s.item == engl && s.text == "ENGL 119 · 1h 5m left",
              "during English it's English, not ECON, got \(s.text)")
        s = status(11, 25)
        check(s.reason == .startingSoon && s.item == econ && s.text == "ECON 101 in 5m", "ECON five minutes out, got \(s.text)")
        s = status(11, 30)
        check(s.reason == .inClass && s.item == econ, "flips to ECON on the minute it starts, got \(s.text)")
        s = status(13, 0)
        check(s.reason == .nextDue && s.item == a4 && s.text == "CS 145 A4 · Tomorrow",
              "idle with nothing pressing: the next assignment, got \(s.reason) \(s.text)")
        s = status(18, 0, day: 30)
        check(s.reason == .urgent && s.item == a4 && s.text == "CS 145 A4 · 4h", "A4 due in four hours is pressing, got \(s.text)")
        s = status(9, 0, day: 30)  // A4 is 13 hours out, below the bar
        check(s.reason == .nextDue && s.item == a4, "13 hours out, A4 is just next due, got \(s.reason)")

        let late = MenuBarStatus.resolve(agenda, weights: weights, now: date(2026, 10, 1, 9), calendar: cal)
        check(late.reason == .urgent && late.text == "CS 145 A4 · late" && late.symbol == "exclamationmark.triangle",
              "missed A4 shows as late, got \(late.text)")
        let doneA4 = work("CS 145", "A4", .assignment, date(2026, 9, 30, 22), done: true)
        s = MenuBarStatus.resolve([cs, econ, engl, doneA4, midterm], weights: weights, now: date(2026, 9, 29, 13), calendar: cal)
        check(s.item == midterm && s.reason == .nextDue, "done work is skipped; with no assignment left, the next assessment, got \(s.text)")

        let quiz = work("MATH 137", "Quiz 3", .quiz, date(2026, 9, 29, 17, 30), end: date(2026, 9, 29, 18, 20))
        s = status(17, 45, [quiz, a4])
        check(s.reason == .inClass && s.text == "MATH 137 Quiz 3 · 35m left", "writing a quiz counts as being in class, got \(s.text)")
        s = status(11, 0, [quiz, a4])
        check(s.reason == .nextDue && s.item == a4, "a quiz later today isn't \"due\": the next assignment is, got \(s.text)")
        s = status(16, 0, [quiz, a4])
        check(s.reason == .urgent && s.item == quiz, "the same quiz 90 minutes out is pressing, got \(s.text)")

        s = status(12, 0, [])
        check(s.reason == .clear && s.text.isEmpty, "nothing on: icon only")

        let hours = AgendaItem(id: "oh", origin: .event("oh"), title: "CS 145 office hours — Troy Vasiga", courseCode: "CS 145",
                               kind: .officeHours, start: date(2026, 9, 29, 11, 30), end: date(2026, 9, 29, 12, 30), isAllDay: false)
        s = status(12, 0, [hours, a4])
        check(s.reason == .nextDue, "office hours stay out of the menu bar while their layer is off, got \(s.text)")
        s = MenuBarStatus.resolve([hours, a4], weights: weights, now: date(2026, 9, 29, 12), officeHours: true, calendar: cal)
        check(s.reason == .inClass && s.text == "CS 145 office hours · 30m left", "switched on, they count, got \(s.text)")

        let skills = work("ENGL 119", "Skills challenge 2: Proposal and pitch", .assignment, date(2026, 10, 2, 23, 59))
        check(MenuBarStatus.name(skills) == "ENGL 119 Skills challenge 2", "subtitle cut, course added, got \(MenuBarStatus.name(skills))")
        check(MenuBarStatus.name(engl) == "ENGL 119", "a class is just its course")
        let long = work("MATH 135", "Assignment about modular arithmetic proofs", .assignment, date(2026, 10, 2, 23, 59))
        check(MenuBarStatus.name(long).count == MenuBarStatus.maxNameLength && MenuBarStatus.name(long).hasSuffix("…"), "long names are cut to fit")
    }

    // MARK: - Week grid hours

    static func timeGrid() {
        func item(_ title: String, _ kind: EventKind, _ start: Date, end: Date? = nil, allDay: Bool = false) -> AgendaItem {
            AgendaItem(id: title, origin: .assessment(UUID()), title: title, courseCode: "CS 145", kind: kind,
                       start: start, end: end ?? start, isAllDay: allDay)
        }
        let lecture = item("Lecture", .lecture, date(2026, 9, 30, 10), end: date(2026, 9, 30, 11, 20))
        check(TimeGrid.hours(for: [lecture], calendar: cal) == 8..<22, "a daytime week keeps 8 AM–10 PM")
        check(TimeGrid.hours(for: [lecture, item("A3", .assignment, date(2026, 9, 30, 22))], calendar: cal) == 8..<23,
              "a 10 PM deadline widens the grid past 10 PM")
        check(TimeGrid.hours(for: [item("Essay", .assignment, date(2026, 10, 8, 23, 59))], calendar: cal) == 8..<24,
              "an 11:59 PM deadline runs the grid to midnight")
        check(TimeGrid.hours(for: [item("Early", .tutorial, date(2026, 10, 1, 7, 30), end: date(2026, 10, 1, 8, 20))], calendar: cal) == 7..<22,
              "a 7:30 AM class opens the grid at 7")
        check(TimeGrid.hours(for: [item("Holiday", .holiday, date(2026, 10, 12), end: date(2026, 10, 13), allDay: true)], calendar: cal) == 8..<22,
              "all-day items leave the hours alone")
    }

    // MARK: - Real course folders (smoke test, informational)

    static func realFolders() {
        let root = URL(fileURLWithPath: NSString(string: "~/Documents/University of Waterloo Classes").expandingTildeInPath)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders.sorted(by: { $0.path < $1.path }) {
            let file = folder.appendingPathComponent("CLAUDE.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let parsed = CourseFolderParser.parse(markdown: text, fallbackYear: 2026)
            let dated = parsed.rows.filter { $0.due != nil }.count
            print("  · \(folder.lastPathComponent): \(parsed.code ?? "?") — \(parsed.rows.count) rows (\(dated) dated), \(parsed.components.count) components, \(parsed.pageMap.count) sections, \(parsed.studyLinks.count) study links\(parsed.teachDontAnswer ? ", teach-don't-answer" : "")")
        }
    }
}
