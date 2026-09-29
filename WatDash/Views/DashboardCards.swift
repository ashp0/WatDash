//
//  DashboardCards.swift
//  WatDash
//

import SwiftUI

// MARK: - Focus

/// The first thing on Today: late work, anything due in the next 48 hours,
/// and midterms or exams this week. The most urgent item gets the room;
/// everything past this week is on the Deadlines screen.
struct FocusCard: View {
    @Environment(AppStore.self) private var store
    var entries: [Focus.Entry]

    var body: some View {
        let tint = entries.isEmpty ? Palette.good : Palette.accentDeep
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Focus", symbol: "scope", trailing: "next 48 hours", tint: tint)
            if let lead = entries.first {
                FocusLead(entry: lead)
                let rest = entries.dropFirst()
                let soon = rest.filter { $0.urgency != .examThisWeek }
                let exams = rest.filter { $0.urgency == .examThisWeek }
                if !rest.isEmpty {
                    Divider()
                    ForEach(soon) { FocusRow(entry: $0) }
                    if !exams.isEmpty {
                        Text("Exams this week")
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, soon.isEmpty ? 0 : 6)
                        ForEach(exams) { FocusRow(entry: $0) }
                    }
                }
            } else {
                allClear
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var allClear: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Palette.good)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing due in the next 48 hours").font(.headline)
                if let next = store.upcomingDeadlines(days: 30).first {
                    Text("Next up: \(next.title)\(next.courseCode.map { " · \($0)" } ?? ""), \(next.start.relativeDayLabel) at \(next.start.shortTime)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Red when late, orange inside a day, plain otherwise: colour is saved
    /// for the moments it should change what you do.
    static func urgencyColor(_ urgency: Focus.Urgency) -> Color {
        switch urgency {
        case .overdue: Palette.bad
        case .within24h: Palette.warn
        case .within48h, .examThisWeek: .primary
        }
    }
}

/// The most urgent item, large: when, what, and how long is left.
struct FocusLead: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var compact
    var entry: Focus.Entry

    var body: some View {
        let item = entry.item
        let color = FocusCard.urgencyColor(entry.urgency)
        let inProgress = !item.isDue && item.contains(store.now)
        HStack(alignment: .top, spacing: 14) {
            DoneCheckbox(item: item, font: .title2)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 5) {
                Text(when(item, inProgress: inProgress))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(entry.urgency == .overdue || entry.urgency == .within24h ? color : .secondary)
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    CourseChip(code: item.courseCode)
                    Text([item.kind.label, item.location, item.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // iPhone: the countdown gets its own line rather than a column.
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        countdownText(item, inProgress: inProgress, color: color)
                        caption(item, inProgress: inProgress)
                    }
                    .padding(.top, 2)
                }
                if item.kind.isSeated, case let .assessment(id) = item.origin, let code = item.courseCode {
                    HStack {
                        SeatingButton()
                        Button {
                            router.sheet = .studyPrompt(code, id)
                        } label: {
                            Label("Study prompt…", systemImage: "terminal")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            if !compact {
                VStack(alignment: .trailing, spacing: 0) {
                    countdownText(item, inProgress: inProgress, color: color)
                    caption(item, inProgress: inProgress)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { router.open(item) }
    }

    private func countdownText(_ item: AgendaItem, inProgress: Bool, color: Color) -> some View {
        Text(countdown(item, inProgress: inProgress))
            .font(.system(size: compact ? 26 : 30, weight: .bold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private func caption(_ item: AgendaItem, inProgress: Bool) -> some View {
        Text(entry.urgency == .overdue ? "late" : (inProgress || item.isDue ? "left" : "to go"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func when(_ item: AgendaItem, inProgress: Bool) -> String {
        if inProgress { return "Happening now · until \(item.end.shortTime)" }
        let day = item.start.relativeDayLabel
        let time = "\(day) · \(item.start.shortTime)"
        if entry.urgency == .overdue { return "Overdue · was due \(time)" }
        return item.isDue ? "Due \(time)" : "Starts \(time)"
    }

    private func countdown(_ item: AgendaItem, inProgress: Bool) -> String {
        if entry.urgency == .overdue { return store.now.compactCountdown(from: item.start) }
        return (inProgress ? item.end : item.start).compactCountdown(from: store.now)
    }
}

/// Every other focus item: one line each, tick to finish.
struct FocusRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var entry: Focus.Entry

    var body: some View {
        HStack(spacing: 8) {
            DoneCheckbox(item: entry.item)
            AgendaRow(item: entry.item, showDate: true, showCountdown: true)
            if entry.urgency == .overdue {
                Text("late")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.bad)
            } else if entry.item.contains(store.now) {
                Text("now · \(entry.item.end.compactCountdown(from: store.now)) left")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.warn)
                    .fixedSize()
            }
        }
        .onTapGesture { router.open(entry.item) }
    }
}

/// Tick box for marked work. Only assessments can be ticked; a deadline from
/// a calendar feed shows its kind instead.
struct DoneCheckbox: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var item: AgendaItem
    var font: Font = .title3

    var body: some View {
        if case .assessment = item.origin {
            Button {
                store.toggleDone(item)
                if !item.isDone { router.show("Marked “\(item.title)” done.") }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(font)
                    .foregroundStyle(item.isDone ? Palette.good : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark not done" : "Mark done")
        } else {
            KindIcon(kind: item.kind, color: store.color(for: item.courseCode))
        }
    }
}

// MARK: - Rest of today

/// Where to be for the rest of the day. Finished classes drop off and marked
/// work is in Focus, so this is just the timetable still ahead.
struct RestOfTodayCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(OfficeHoursLayer.key) private var showOfficeHours = false

    var body: some View {
        let now = store.now
        let items = store.agenda(on: now).filter { shows($0) && $0.end > now }
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Rest of today", symbol: "calendar", trailing: items.isEmpty ? nil : "\(items.count) left")
                if items.isEmpty {
                    Text(tomorrowLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    if !item.isAllDay && item.contains(now) {
                        current(item)
                    } else {
                        AgendaRow(item: item)
                            .onTapGesture { router.open(item) }
                    }
                }
            }
        }
    }

    private func shows(_ item: AgendaItem) -> Bool {
        !item.kind.isAssessment && !item.isDue && (showOfficeHours || item.kind != .officeHours)
    }

    private var tomorrowLine: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.now) ?? store.now
        guard let first = store.agenda(on: tomorrow).first(where: { shows($0) && !$0.isAllDay }) else {
            return "Nothing else on today."
        }
        return "Nothing else on today. Tomorrow starts with \(first.title) at \(first.start.shortTime)."
    }

    private func current(_ item: AgendaItem) -> some View {
        let color = store.color(for: item.courseCode)
        let progress = min(1, max(0, store.now.timeIntervalSince(item.start) / max(1, item.end.timeIntervalSince(item.start))))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                AgendaRow(item: item)
                Text("Now · until \(item.end.shortTime)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .fixedSize()
            }
            ProgressView(value: progress)
                .tint(color)
                .controlSize(.small)
                .padding(.leading, 71)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { router.open(item) }
    }
}

// MARK: - Notices

/// Captures waiting for a yes: one line, only when there are any.
struct InboxNotice: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let count = store.proposedEvents.count
        if count > 0 {
            Notice(symbol: "tray", title: "\(count) capture\(count == 1 ? "" : "s") to confirm",
                   detail: "WatDash wasn't sure about \(count == 1 ? "this one" : "these"). Add or discard.") {
                Button("Review…") { router.sheet = .inbox }
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
                .linkButtonStyle()
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String, _ action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Palette.accent.opacity(0.2), in: Circle())
            // The button beside the text where there's room, under it on a phone.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    stepText(title, detail)
                    Spacer()
                    Button(action, action: perform)
                }
                VStack(alignment: .leading, spacing: 6) {
                    stepText(title, detail)
                    Button(action, action: perform)
                }
            }
        }
    }

    private func stepText(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Setup

/// Shown on Today until the term is fully set up: one line naming the next
/// missing step, with the button that fixes it.
struct SetupNotice: View {
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

    var body: some View {
        let steps = steps
        if !dismissed, !store.courses.isEmpty, let next = steps.first(where: { !$0.done }) {
            Notice(symbol: "checklist", title: "Finish setting up · \(steps.filter(\.done).count) of \(steps.count) done",
                   detail: "\(next.title): \(next.detail)") {
                Button(next.action, action: next.perform)
                Button { dismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide this reminder")
            }
        }
    }
}
