//
//  CourseDetailView.swift
//  WatDash
//

import SwiftUI

struct CourseDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course
    @State private var tab = "grades"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case "overview": CourseOverview(course: course)
            case "timetable": CourseTimetable(course: course)
            case "study": CourseStudyTab(course: course)
            default: CourseGradesEditor(course: course)
            }
        }
        .navigationTitle(course.code)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Palette.color(course.colorIndex).gradient)
                .frame(width: 44, height: 44)
                .overlay(Text(course.subject.prefix(2)).font(.headline).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(course.code).font(.title2.weight(.bold))
                Text([course.title, "\(course.units.formatted()) units", course.sections.isEmpty ? nil : course.sections.joined(separator: ", ")]
                    .compactMap { $0?.nilIfEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                Text("Grades").tag("grades")
                Text("Overview").tag("overview")
                Text("Timetable").tag("timetable")
                Text("Study").tag("study")
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
            Menu {
                Button("Edit Course…") { router.sheet = .courseEditor(course.id) }
                Button("New Assessment…") { router.sheet = .newAssessment(course.code) }
                if let folder = course.folderURL {
                    Button("Show Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Grades editor

struct CourseGradesEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        let result = store.courseResult(course.code)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let result, result.requirement != .noScheme {
                    Card {
                        HStack(spacing: 22) {
                            stat("Current", result.current)
                            stat("Projected", result.projected)
                            stat("Banked", result.floor)
                            stat("Ceiling", result.ceiling)
                            VStack(alignment: .leading, spacing: 4) {
                                GradeBar(floor: result.floor, ceiling: result.ceiling, projected: result.projected,
                                         low: result.projectedLow, high: result.projectedHigh,
                                         target: store.settings.targetAverage, color: Palette.color(course.colorIndex))
                                Text(SnapshotWriter.requirementText(result.requirement)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SchemeEditor(course: course)
                AssessmentTable(course: course)
            }
            .padding(20)
        }
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { $0.oneDecimal } ?? "—").font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

struct SchemeEditor: View {
    @Environment(AppStore.self) private var store
    var course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Grading scheme").font(.title3.weight(.semibold))
                Text("\(course.scheme.totalWeight.noDecimals)%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(abs(course.scheme.totalWeight - 100) < 0.01 ? Palette.good : Palette.warn)
                Spacer()
                Button {
                    var copy = course
                    copy.scheme.components.append(GradeComponent(name: "New component", weight: 0))
                    store.updateCourse(copy)
                } label: { Label("Component", systemImage: "plus") }
            }
            Card(padding: 10) {
                VStack(spacing: 6) {
                    HStack {
                        Text("Component").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Weight %").frame(width: 70)
                        Text("Items").frame(width: 60)
                        Text("Drop lowest").frame(width: 80)
                        Text("Exam").frame(width: 44)
                        Color.clear.frame(width: 24)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(course.scheme.components) { component in
                        ComponentRow(course: course, component: component)
                    }
                    if course.scheme.components.isEmpty {
                        Text("No components. Add them from the outline's assessment table (or import the outline).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            RulesEditor(course: course)
        }
    }
}

struct ComponentRow: View {
    @Environment(AppStore.self) private var store
    var course: Course
    var component: GradeComponent

    var body: some View {
        HStack {
            TextField("Name", text: bind(\.name)).textFieldStyle(.roundedBorder)
            TextField("", value: bind(\.weight), format: .number).frame(width: 70).textFieldStyle(.roundedBorder)
            TextField("", value: Binding(get: { component.expectedCount ?? 0 }, set: { update { $0.expectedCount = $1 > 0 ? $1 : nil }($0) }), format: .number)
                .frame(width: 60).textFieldStyle(.roundedBorder)
            Stepper(value: bind(\.dropLowest), in: 0...10) { Text("\(component.dropLowest)").monospacedDigit() }
                .frame(width: 80)
            Toggle("", isOn: bind(\.isExam)).labelsHidden().frame(width: 44)
            Button(role: .destructive) {
                var copy = course
                copy.scheme.components.removeAll { $0.id == component.id }
                copy.scheme.rules.removeAll { rule in
                    switch rule {
                    case let .replaceIfBetter(target, with): target == component.id || with == component.id
                    case let .mustPass(ids, _): ids.contains(component.id)
                    }
                }
                store.updateCourse(copy)
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .frame(width: 24)
        }
    }

    private func update<V>(_ apply: @escaping (inout GradeComponent, V) -> Void) -> (V) -> Void {
        { value in
            var copy = course
            guard let index = copy.scheme.components.firstIndex(where: { $0.id == component.id }) else { return }
            apply(&copy.scheme.components[index], value)
            store.updateCourse(copy)
        }
    }

    private func bind<V>(_ keyPath: WritableKeyPath<GradeComponent, V>) -> Binding<V> {
        Binding(get: { component[keyPath: keyPath] }, set: { update { $0[keyPath: keyPath] = $1 }($0) })
    }
}

struct RulesEditor: View {
    @Environment(AppStore.self) private var store
    var course: Course

    var body: some View {
        let exams = course.scheme.components.filter(\.isExam)
        let midterm = course.scheme.components.first { $0.name.lowercased().contains("midterm") }
        let final = course.scheme.components.first { $0.name.lowercased().contains("final") }
        let hasReplace = course.scheme.rules.contains { if case .replaceIfBetter = $0 { true } else { false } }
        let hasPass = course.scheme.rules.contains { if case .mustPass = $0 { true } else { false } }
        HStack(spacing: 18) {
            if let midterm, let final {
                Toggle("Final replaces midterm if better", isOn: Binding(
                    get: { hasReplace },
                    set: { on in
                        var copy = course
                        copy.scheme.rules.removeAll { if case .replaceIfBetter = $0 { true } else { false } }
                        if on { copy.scheme.rules.append(.replaceIfBetter(target: midterm.id, with: final.id)) }
                        store.updateCourse(copy)
                    }
                ))
            }
            if !exams.isEmpty {
                Toggle("Must pass the exams (≥ 50%) to pass the course", isOn: Binding(
                    get: { hasPass },
                    set: { on in
                        var copy = course
                        copy.scheme.rules.removeAll { if case .mustPass = $0 { true } else { false } }
                        if on { copy.scheme.rules.append(.mustPass(components: exams.map(\.id), threshold: 50)) }
                        store.updateCourse(copy)
                    }
                ))
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

struct AssessmentTable: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        let items = store.assessments.filter { $0.courseCode == course.code }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assessments").font(.title3.weight(.semibold))
                Spacer()
                Button { router.sheet = .newAssessment(course.code) } label: { Label("Assessment", systemImage: "plus") }
            }
            Card(padding: 10) {
                VStack(spacing: 4) {
                    HStack {
                        Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Component").frame(width: 130, alignment: .leading)
                        Text("Date").frame(width: 110, alignment: .leading)
                        Text("Score").frame(width: 120)
                        Text("What-if %").frame(width: 150)
                        Text("Excused").frame(width: 56)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(items) { assessment in
                        AssessmentRow(course: course, assessment: assessment)
                        Divider()
                    }
                    if items.isEmpty {
                        Text("No assessments. Scan the course folder or add them by hand.").foregroundStyle(.secondary).padding(8)
                    }
                }
            }
        }
    }
}

struct AssessmentRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course
    var assessment: Assessment

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: assessment.kind.symbol).foregroundStyle(Palette.color(course.colorIndex)).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(assessment.title).lineLimit(1)
                    if assessment.kind.isSeated && !assessment.isGraded {
                        HStack(spacing: 6) {
                            if let location = assessment.location {
                                Text(location).foregroundStyle(.secondary).lineLimit(1)
                            }
                            SeatingButton(compact: true)
                        }
                        .font(.caption)
                    }
                }
                if assessment.componentID == nil && !course.scheme.components.isEmpty {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.warn).help("Not in any component, so it doesn't count yet")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { router.sheet = .editAssessment(assessment.id) }

            Picker("", selection: Binding(
                get: { assessment.componentID },
                set: { var copy = assessment; copy.componentID = $0; store.updateAssessment(copy) }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(course.scheme.components) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .frame(width: 130)

            Text(assessment.due.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "TBA")
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            HStack(spacing: 2) {
                TextField("—", value: Binding(
                    get: { assessment.score },
                    set: { var copy = assessment; copy.score = $0; if $0 != nil { copy.isDone = true }; store.updateAssessment(copy) }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                Text("/")
                TextField("", value: Binding(
                    get: { assessment.outOf },
                    set: { var copy = assessment; copy.outOf = max(0.01, $0); store.updateAssessment(copy) }
                ), format: .number)
                .frame(width: 44)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)

            HStack(spacing: 4) {
                if assessment.isGraded {
                    Text(assessment.percent.map { "\($0.oneDecimal)%" } ?? "").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Slider(value: Binding(
                        get: { assessment.whatIf ?? 0 },
                        set: { var copy = assessment; copy.whatIf = $0 < 1 ? nil : $0.rounded(); store.updateAssessment(copy) }
                    ), in: 0...100)
                    Text(assessment.whatIf.map { $0.noDecimals } ?? "auto").font(.caption.monospacedDigit()).frame(width: 30)
                }
            }
            .frame(width: 150)

            Toggle("", isOn: Binding(
                get: { assessment.isExcused },
                set: { var copy = assessment; copy.isExcused = $0; store.updateAssessment(copy) }
            ))
            .labelsHidden()
            .frame(width: 56)
        }
        .font(.callout)
        .contextMenu {
            Button("Edit…") { router.sheet = .editAssessment(assessment.id) }
            Button("Delete", role: .destructive) { store.deleteAssessment(id: assessment.id) }
        }
    }
}

// MARK: - Overview

struct CourseOverview: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        let upcoming = store.upcomingDeadlines(days: 60).filter { $0.courseCode == course.code }.prefix(8)
        let meetings = store.events.filter { $0.courseCode == course.code && $0.recurrence != nil && $0.status == .confirmed }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            CardHeader(title: "Coming up", symbol: "flag", tint: Palette.color(course.colorIndex))
                            if upcoming.isEmpty { Text("Nothing dated.").foregroundStyle(.secondary) }
                            ForEach(Array(upcoming)) { AgendaRow(item: $0, showDate: true, showCountdown: true) }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            CardHeader(title: "Weekly meetings", symbol: "calendar", tint: Palette.color(course.colorIndex))
                            if meetings.isEmpty {
                                Text("No class times yet. Import your Quest schedule or pick sections from the outline.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            ForEach(meetings) { event in
                                HStack {
                                    Image(systemName: event.kind.symbol).frame(width: 18)
                                    Text(event.title).font(.callout.weight(.medium))
                                    Spacer()
                                    Text("\(daysText(event.recurrence?.weekdays ?? [])) \(event.start.shortTime)").font(.callout.monospacedDigit())
                                    Text(event.location ?? "").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: "Files", symbol: "folder", tint: Palette.color(course.colorIndex))
                        if let folder = course.folderURL {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([folder]) } label: { Label(folder.path, systemImage: "folder") }
                                .buttonStyle(.link)
                            if let notes = course.notesURL {
                                Button { NSWorkspace.shared.open(notes) } label: { Label("Course notes: \(notes.lastPathComponent)", systemImage: "doc.richtext") }
                                    .buttonStyle(.link)
                            }
                            let manifest = folder.appendingPathComponent("CLAUDE.md")
                            if FileManager.default.fileExists(atPath: manifest.path) {
                                Button { NSWorkspace.shared.open(manifest) } label: { Label("CLAUDE.md", systemImage: "doc.text") }
                                    .buttonStyle(.link)
                            }
                        } else {
                            Text("No course folder linked. Scan course folders to link it.").foregroundStyle(.secondary)
                        }
                        if course.teachDontAnswer {
                            Label("This course's rule: teach with different examples; never hand over assignment answers.", systemImage: "hand.raised")
                                .font(.callout).foregroundStyle(Palette.accentDeep)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct CourseTimetable: View {
    @Environment(AppStore.self) private var store
    var course: Course

    var body: some View {
        let window = DateInterval(start: store.settings.termStart, end: store.settings.termEnd.addingTimeInterval(86_400))
        let items = store.agenda(in: window).filter { $0.courseCode == course.code }
        List {
            ForEach(items) { item in
                AgendaRow(item: item, showDate: true)
                    .opacity(item.end < store.now ? 0.45 : 1)
            }
        }
        .listStyle(.inset)
        .overlay { if items.isEmpty { EmptyState(symbol: "calendar", title: "Nothing scheduled", message: "Import this course's schedule.") } }
    }
}
