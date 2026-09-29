//
//  DashboardCards.swift
//  WatDash
//

import Charts
import SwiftUI

// MARK: - Now & next

struct NowNextCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let (current, next) = store.nowAndNext()
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Now & next", symbol: "clock")
                if let current {
                    let progress = min(1, max(0, store.now.timeIntervalSince(current.start) / max(1, current.end.timeIntervalSince(current.start))))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(store.color(for: current.courseCode))
                        Text(current.title).font(.title3.weight(.semibold)).lineLimit(1)
                        Text([current.location, "ends \(current.end.shortTime)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                        ProgressView(value: progress).tint(store.color(for: current.courseCode))
                    }
                }
                if let next {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(next.title).font(current == nil ? .title3.weight(.semibold) : .headline).lineLimit(1)
                            Spacer()
                            Text("in \(next.start.compactCountdown(from: store.now))")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.accentDeep)
                        }
                        Text([next.start.relativeDayLabel + " " + next.start.shortTime, next.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else if current == nil {
                    Text("Nothing on the timetable yet.")
                        .foregroundStyle(.secondary)
                }
                let later = laterToday(after: next)
                if !later.isEmpty {
                    Divider()
                    Text("LATER TODAY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(later) { AgendaRow(item: $0) }
                }
            }
        }
    }

    private func laterToday(after next: AgendaItem?) -> [AgendaItem] {
        guard let next else { return [] }
        return Array(store.agenda(on: store.now).filter { $0.start > next.start && !$0.isAllDay }.prefix(3))
    }
}

// MARK: - Today

struct TodayCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let items = store.agenda(on: store.now)
        let tomorrow = store.agenda(on: Calendar.current.date(byAdding: .day, value: 1, to: store.now) ?? store.now)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Today", symbol: "list.bullet.rectangle", trailing: "\(items.count) item\(items.count == 1 ? "" : "s")")
                if items.isEmpty {
                    Text("Nothing today.").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        AgendaRow(item: item)
                            .opacity(item.end < store.now && !item.isDue ? 0.45 : 1)
                            .overlay(alignment: .leading) {
                                if item.contains(store.now) && !item.isDue {
                                    Circle().fill(Palette.bad).frame(width: 7, height: 7).offset(x: 62)
                                }
                            }
                            .onTapGesture { open(item) }
                    }
                }
                if !tomorrow.isEmpty {
                    Divider()
                    Text("Tomorrow starts with \(tomorrow[0].title) at \(tomorrow[0].start.shortTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func open(_ item: AgendaItem) {
        switch item.origin {
        case let .event(id): router.sheet = .editEvent(id)
        case let .assessment(id): router.sheet = .editAssessment(id)
        }
    }
}

// MARK: - Deadlines

struct DeadlinesCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let items = Array(store.upcomingDeadlines(days: 14).prefix(7))
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Upcoming deadlines", symbol: "flag", trailing: "14 days")
                if items.isEmpty {
                    Text("Nothing due in the next two weeks.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button {
                            store.toggleDone(item)
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Palette.good : .secondary)
                        }
                        .buttonStyle(.plain)
                        AgendaRow(item: item, showDate: true, showCountdown: true)
                            .onTapGesture {
                                if case let .assessment(id) = item.origin { router.sheet = .editAssessment(id) }
                            }
                    }
                }
                if store.upcomingDeadlines(days: 14).count > items.count {
                    Button("See all deadlines") { router.selection = .deadlines }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Overload tracker

struct OverloadCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let term = store.term
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Overload tracker", symbol: "gauge.with.dots.needle.67percent",
                           trailing: "target \(Int(term.target))%", tint: Palette.margin(term.margin))
                HStack(spacing: 18) {
                    MarginRing(value: term.projected, target: term.target)
                        .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        if let margin = term.margin {
                            Text("\(margin.signedOneDecimal) points")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.margin(margin))
                            Text(margin >= 0 ? "above the 80% line for a sixth course" : "below the 80% line for a sixth course")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Waiting for marks").font(.headline)
                            Text("Add a grading scheme and a score or two to project your average.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let p = term.probabilityAtLeastTarget {
                            Label("\(Int((p * 100).rounded()))% chance of ≥ \(Int(term.target))", systemImage: "chart.bar.xaxis")
                                .font(.caption)
                        }
                        Label(SnapshotWriter.requirementText(term.requiredOnRemaining), systemImage: "target")
                            .font(.caption)
                        if let low = term.low, let high = term.high {
                            Text("Likely range \(low.oneDecimal)–\(high.oneDecimal)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Cumulative average (not GPA), unit-weighted, with course grades rounded like the transcript.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onTapGesture { router.selection = .grades }
    }
}

// MARK: - Leverage

struct LeverageCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let horizon = store.now.addingTimeInterval(35 * 86_400)
        let items = store.term.leverage.filter { item in item.due.map { $0 > store.now && $0 <= horizon } ?? false }.prefix(5)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Highest-impact work", symbol: "arrow.up.right.circle", trailing: "next 5 weeks")
                if items.isEmpty {
                    Text("Once schemes are in, this ranks upcoming work by how much it moves your average.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(items)) { item in
                    HStack(spacing: 8) {
                        CourseChip(code: item.code, compact: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text("\(item.courseWeight.oneDecimal)% of the course\(item.due.map { " · \($0.dayMonth)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(String(format: "%.2f", item.termImpact * 10))")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.accentDeep)
                            .help("Every 10 points on this moves your term average by this much")
                    }
                }
                if !items.isEmpty {
                    Text("Term-average points per 10 marks on the item.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .onTapGesture { router.selection = .grades }
    }
}

// MARK: - Week load

struct WeekLoadCard: View {
    @Environment(AppStore.self) private var store

    struct Bar: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(series)" }
        var day: Date
        var series: String
        var hours: Double
    }

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: store.now)
        let items = store.agenda(in: DateInterval(start: start, duration: 14 * 86_400))
        var bars: [Bar] = []
        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let today = items.filter { calendar.isDate($0.start, inSameDayAs: day) && !$0.isAllDay }
            let classes = today.filter { $0.kind.isClassMeeting }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 }
            let tests = today.filter { $0.kind == .quiz || $0.kind == .test || $0.kind == .exam }.reduce(0) { $0 + max(1, $1.end.timeIntervalSince($1.start) / 3600) }
            let due = Double(today.filter(\.isDue).count)
            bars.append(Bar(day: day, series: "Classes", hours: classes))
            bars.append(Bar(day: day, series: "Quizzes & exams", hours: tests * 2))
            bars.append(Bar(day: day, series: "Deadlines", hours: due * 1.5))
        }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Two weeks at a glance", symbol: "chart.bar", trailing: "load score")
                Chart(bars) { bar in
                    BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Load", bar.hours))
                        .foregroundStyle(by: .value("Kind", bar.series))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([
                    "Classes": Color.secondary.opacity(0.45),
                    "Quizzes & exams": Palette.bad,
                    "Deadlines": Palette.accent,
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 150)
            }
        }
    }
}

// MARK: - Course grades

struct CourseGradesCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Course grades", symbol: "percent", trailing: "● projected  ▮ banked")
                ForEach(store.courses.filter(\.countsTowardAverage)) { course in
                    let result = store.courseResult(course.code)
                    HStack(spacing: 12) {
                        CourseChip(code: course.code)
                            .frame(width: 84, alignment: .leading)
                        if let result, result.requirement != .noScheme {
                            GradeBar(floor: result.floor, ceiling: result.ceiling, projected: result.projected,
                                     low: result.projectedLow, high: result.projectedHigh,
                                     target: store.settings.targetAverage, color: Palette.color(course.colorIndex))
                            Text(result.current.map { $0.oneDecimal } ?? "—")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        } else {
                            Text("No grading scheme yet").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.selection = .course(course.id) }
                }
                if store.courses.isEmpty {
                    Text("Import your courses to see grades.").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Import hub

struct ImportHubCard: View {
    @Environment(Router.self) private var router

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Import", symbol: "square.and.arrow.down", trailing: "drop .ics files anywhere")
                ImportTileGrid(compact: true)
            }
        }
    }
}

// MARK: - Study

struct StudyCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let next = store.upcomingDeadlines(days: 21).first { $0.kind == .quiz || $0.kind == .test || $0.kind == .exam }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Study", symbol: "book")
                if let next, case let .assessment(id) = next.origin, let assessment = store.assessment(id: id),
                   let course = store.course(code: assessment.courseCode) {
                    HStack {
                        CourseChip(code: course.code)
                        Text(assessment.title).font(.headline)
                        Spacer()
                        Text(next.start.compactCountdown(from: store.now)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let coverage = assessment.coverage {
                        Text("Covers \(coverage)").font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button {
                            router.sheet = .studyPrompt(course.code, assessment.id)
                        } label: {
                            Label("Claude Code prompt…", systemImage: "terminal")
                        }
                        if let link = course.studyLinks.last, let url = link.resolvedURL {
                            Button { NSWorkspace.shared.open(url) } label: { Label(link.title, systemImage: "safari") }
                                .lineLimit(1)
                        }
                    }
                    .controlSize(.small)
                } else {
                    Text("No quizzes or exams in the next three weeks.").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Countdown

struct CountdownCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Next exam", symbol: "hourglass")
                if let exam = store.nextExam() {
                    let days = Calendar.current.days(from: store.now, to: exam.start)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(days)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(store.color(for: exam.courseCode))
                            .monospacedDigit()
                        Text(days == 1 ? "day" : "days").font(.title3).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        CourseChip(code: exam.courseCode)
                        Text(exam.title).font(.headline)
                    }
                    Text("\(exam.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) at \(exam.start.shortTime)\(exam.location.map { " · \($0)" } ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                    if let detail = exam.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text("No midterms or exams dated yet.").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Seat watch

struct SeatWatchCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Seat watch", symbol: "chair", trailing: Keychain.get(.openData) == nil ? "needs Open Data key" : nil)
                if store.seatWatches.isEmpty {
                    Text("Watch a section (say, the Russian course you want as a sixth course) and get notified when a seat opens.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(store.seatWatches) { watch in
                    HStack {
                        Text(watch.courseCode).font(.callout.weight(.semibold))
                        if !watch.section.isEmpty { Text(watch.section).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let open = watch.openSeats, let capacity = watch.capacity {
                            Text(open > 0 ? "\(open) open" : "Full (\(capacity))")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(open > 0 ? Palette.good : Palette.bad)
                        } else {
                            Text("not checked").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Manage…") { router.sheet = .openData }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}

// MARK: - Inbox

struct InboxCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let proposed = store.proposedEvents
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Inbox", symbol: "tray", trailing: proposed.isEmpty ? nil : "\(proposed.count) to confirm")
                if proposed.isEmpty {
                    Text("Captures WatDash wasn't sure about wait here for a yes. All clear.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(proposed.prefix(5)) { event in
                    InboxRow(event: event)
                }
            }
        }
    }
}

struct InboxRow: View {
    @Environment(AppStore.self) private var store
    var event: DashEvent

    var body: some View {
        HStack(spacing: 8) {
            KindIcon(kind: event.kind, color: store.color(for: event.courseCode))
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(event.start.dayMonth), \(event.start.shortTime)\(event.location.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.accept(proposed: event.id) } label: { Image(systemName: "checkmark") }
                .help("Add it")
            Button { store.deleteEvent(id: event.id) } label: { Image(systemName: "xmark") }
                .help("Discard")
        }
        .controlSize(.small)
    }
}

// MARK: - Onboarding

struct OnboardingCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Let's fill in your term").font(.title2.weight(.semibold))
                Text("Three imports cover almost everything, and each takes seconds. Nothing is retyped.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Course folders", "Reads each course's CLAUDE.md: assessments with dates, grading scheme, notes page map and study pages.", "Scan \(URL(fileURLWithPath: store.settings.classesFolderPath).lastPathComponent)") {
                        router.sheet = .courseFolders
                    }
                    step(2, "Your class schedule", "Quest → My Class Schedule → List View: download the .ics, or copy the page and paste it.", "Paste Quest schedule") {
                        router.sheet = .questPaste
                    }
                    step(3, "UW holidays", "Thanksgiving and other holidays cancel classes automatically. No key needed.", "Add holidays") {
                        Task {
                            let summary = try? await ImportService.shared.importHolidays()
                            router.show(summary.map { "\($0.title): \($0.detail)" } ?? "Couldn't reach the Open Data holidays feed.")
                        }
                    }
                }
                Button("Or explore with a sample term") {
                    store.replaceAll(with: DemoSeeder.sampleTerm())
                }
                .buttonStyle(.link)
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String, _ action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Palette.accent.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, action: perform)
        }
    }
}

// MARK: - Setup checklist

/// Shown on Today until the term is fully set up: names exactly what's
/// missing and opens the right screen for it.
struct SetupChecklistCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("setup.dismissed") private var dismissed = false

    struct Step: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var done: Bool
        var action: String
        var perform: () -> Void
    }

    var steps: [Step] {
        let counted = store.courses.filter(\.countsTowardAverage)
        let missingSchemes = counted.filter { $0.scheme.totalWeight <= 0 }
        let hasClasses = store.events.contains { $0.kind.isClassMeeting && $0.status == .confirmed }
        let hasMarks = store.assessments.contains(where: \.isGraded)
        let hasHolidays = store.sources.contains { $0.kind == .holidays }
        return [
            Step(title: "Courses", detail: store.courses.isEmpty ? "Scan your course folders." : "\(store.courses.count) courses in.",
                 done: !store.courses.isEmpty, action: "Scan folders") { router.sheet = .courseFolders },
            Step(title: "Class times", detail: "Paste your Quest schedule (or drop its .ics), or pick your sections from a saved outline.",
                 done: hasClasses, action: "Paste Quest schedule") { router.sheet = .questPaste },
            Step(title: "Grading schemes",
                 detail: missingSchemes.isEmpty ? "Every course has one." : "Missing for \(missingSchemes.map(\.code).joined(separator: ", ")): copy the weights from the outline.",
                 done: missingSchemes.isEmpty && !counted.isEmpty, action: "Add scheme") {
                     if let first = missingSchemes.first { router.selection = .course(first.id) } else { router.selection = .grades }
                 },
            Step(title: "Marks so far", detail: "Enter the marks you already have so the projection has something to go on.",
                 done: hasMarks, action: "Enter marks") {
                     if let course = counted.first(where: { $0.scheme.totalWeight > 0 }) { router.selection = .course(course.id) } else { router.selection = .grades }
                 },
            Step(title: "Holidays", detail: "Thanksgiving and other holidays cancel classes automatically.",
                 done: hasHolidays, action: "Add holidays") {
                     Task {
                         let summary = try? await ImportService.shared.importHolidays()
                         router.show(summary.map { "\($0.title): \($0.detail)" } ?? "Couldn't reach the holidays feed.")
                     }
                 },
        ]
    }

    var isComplete: Bool { steps.allSatisfy(\.done) }

    var body: some View {
        if !dismissed && !isComplete && !store.courses.isEmpty {
            let steps = steps
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardHeader(title: "Finish setting up", symbol: "checklist",
                                   trailing: "\(steps.filter(\.done).count) of \(steps.count) done")
                        Button { dismissed = true } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Hide this checklist")
                    }
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.done ? Palette.good : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title).font(.callout.weight(.semibold))
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !step.done {
                                Button(step.action, action: step.perform).controlSize(.small)
                            }
                        }
                        .opacity(step.done ? 0.6 : 1)
                    }
                }
            }
        }
    }
}
