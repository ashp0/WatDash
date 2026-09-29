//
//  Editors.swift
//  WatDash
//

import SwiftUI

// MARK: - Event

struct EventEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var eventID: String?
    var initialDate: Date?

    @State private var event = DashEvent(id: UUID().uuidString, title: "", kind: .event, start: .now, end: .now)
    @State private var repeats = false
    @State private var repeatUntil = Date.now
    @State private var weekdays: Set<Int> = []
    @State private var loaded = false

    var body: some View {
        SheetScaffold(title: eventID == nil ? "New event" : "Edit event", subtitle: "Recurring meetings are stored once and expanded around holidays and skipped dates.") {
            Form {
                TextField("Title", text: $event.title)
                Picker("Course", selection: $event.courseCode) {
                    Text("None").tag(String?.none)
                    ForEach(store.courses) { Text($0.code).tag(Optional($0.code)) }
                }
                Picker("Kind", selection: $event.kind) {
                    ForEach(EventKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Toggle("All day", isOn: $event.isAllDay)
                DatePicker("Starts", selection: $event.start, displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $event.end, in: event.start..., displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location", text: Binding(get: { event.location ?? "" }, set: { event.location = $0.nilIfEmpty }))
                Toggle("Repeats weekly", isOn: $repeats)
                if repeats {
                    HStack {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Toggle(["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day], isOn: Binding(
                                get: { weekdays.contains(day) },
                                set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                    DatePicker("Until", selection: $repeatUntil, displayedComponents: [.date])
                }
                if event.kind == .holiday {
                    Toggle("Cancels classes that day", isOn: $event.cancelsClasses)
                }
                TextField("Notes", text: Binding(get: { event.notes ?? "" }, set: { event.notes = $0.nilIfEmpty }), axis: .vertical)
                    .lineLimit(2...5)
                if let source = store.source(id: event.sourceID) {
                    LabeledContent("Source", value: source.name)
                }
            }
            .formStyle(.grouped)
        } actions: {
            if eventID != nil {
                Button("Delete", role: .destructive) {
                    store.deleteEvent(id: event.id)
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(event.title.trimmed.isEmpty)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let eventID, let existing = store.event(id: eventID) {
            event = existing
            repeats = existing.recurrence != nil
            weekdays = Set(existing.recurrence?.weekdays ?? [])
            repeatUntil = existing.recurrence?.until ?? store.settings.termEnd
        } else {
            let start = initialDate ?? Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
            event.start = start
            event.end = start.addingTimeInterval(3600)
            repeatUntil = store.settings.termEnd
            weekdays = [Calendar.current.component(.weekday, from: start)]
        }
    }

    private func save() {
        var saved = event
        saved.title = saved.title.trimmed
        if saved.end < saved.start { saved.end = saved.start }
        if saved.isAllDay {
            let calendar = Calendar.current
            saved.start = calendar.startOfDay(for: saved.start)
            saved.end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: saved.end)) ?? saved.end
        }
        saved.recurrence = repeats ? .weekly(on: weekdays.isEmpty ? [Calendar.current.component(.weekday, from: saved.start)] : Array(weekdays).sorted(),
                                             until: Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: repeatUntil)) : nil
        if saved.timeZoneID == nil { saved.timeZoneID = TimeZone.current.identifier }
        if saved.sourceID == nil {
            let source = store.sources.first { $0.kind == .manual } ?? store.addSource(DataSource(kind: .manual, name: "Added by hand"))
            saved.sourceID = source.id
        }
        if eventID == nil { store.addEvent(saved) } else { store.updateEvent(saved) }
        dismiss()
    }
}

// MARK: - Assessment

struct AssessmentEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var assessmentID: UUID?
    var courseCode: String?

    @State private var item = Assessment(courseCode: "", title: "")
    @State private var hasDate = true
    @State private var hasEnd = false
    @State private var loaded = false

    var body: some View {
        let course = store.course(code: item.courseCode)
        SheetScaffold(title: assessmentID == nil ? "New assessment" : item.title, subtitle: "Marks feed the grade engine through the component they belong to.") {
            Form {
                Picker("Course", selection: $item.courseCode) {
                    ForEach(store.courses) { Text($0.code).tag($0.code) }
                }
                TextField("Title", text: $item.title)
                Picker("Kind", selection: $item.kind) {
                    ForEach([EventKind.quiz, .test, .exam, .assignment, .deadline]) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Picker("Component", selection: $item.componentID) {
                    Text("None").tag(UUID?.none)
                    ForEach(course?.scheme.components ?? []) { Text("\($0.name) (\($0.weight.noDecimals)%)").tag(Optional($0.id)) }
                }
                Toggle("Dated", isOn: $hasDate)
                if hasDate {
                    DatePicker(item.kind.isDue ? "Due" : "Starts", selection: Binding(get: { item.due ?? .now }, set: { item.due = $0 }))
                    if !item.kind.isDue {
                        Toggle("Custom end time", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Ends", selection: Binding(get: { item.end ?? item.due ?? .now }, set: { item.end = $0 }))
                        }
                    }
                }
                TextField("Covers", text: Binding(get: { item.coverage ?? "" }, set: { item.coverage = $0.nilIfEmpty }), prompt: Text("e.g. 1.4–1.5, 2.1"))
                TextField("Location", text: Binding(get: { item.location ?? "" }, set: { item.location = $0.nilIfEmpty }))
                HStack {
                    TextField("Score", value: $item.score, format: .number)
                    Text("out of")
                    TextField("", value: $item.outOf, format: .number).frame(width: 70)
                    if let percent = item.percent { Text("= \(percent.oneDecimal)%").foregroundStyle(.secondary) }
                }
                Toggle("Excused (weight moves to the others)", isOn: $item.isExcused)
                Toggle("Done", isOn: $item.isDone)
                TextField("Notes", text: Binding(get: { item.notes ?? "" }, set: { item.notes = $0.nilIfEmpty }), axis: .vertical)
            }
            .formStyle(.grouped)
        } actions: {
            if assessmentID != nil {
                Button("Delete", role: .destructive) {
                    store.deleteAssessment(id: item.id)
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") {
                var saved = item
                if !hasDate { saved.due = nil; saved.end = nil }
                if !hasEnd { saved.end = nil }
                if saved.score != nil { saved.isDone = true }
                if assessmentID == nil { store.addAssessment(saved) } else { store.updateAssessment(saved) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(item.title.trimmed.isEmpty || item.courseCode.isEmpty)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let assessmentID, let existing = store.assessment(id: assessmentID) {
                item = existing
                hasDate = existing.due != nil
                hasEnd = existing.end != nil && existing.end != existing.due
            } else {
                item.courseCode = courseCode ?? store.courses.first?.code ?? ""
                item.due = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))?.addingTimeInterval(16 * 3600 + 300)
            }
        }
        .onChange(of: item.kind) { _, kind in
            if item.componentID == nil, let course {
                item.componentID = course.scheme.guessComponent(kind: kind, title: item.title)?.id
            }
        }
    }
}

// MARK: - Course

struct CourseEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var courseID: UUID
    @State private var course = Course(code: "")
    @State private var sectionsText = ""
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: "Edit course", subtitle: "Sections are used to pull class times from Open Data and saved outlines.") {
            Form {
                TextField("Code", text: $course.code)
                TextField("Title", text: $course.title)
                TextField("Units", value: $course.units, format: .number)
                Toggle("Counts toward my average", isOn: $course.countsTowardAverage)
                Toggle("Teach, don't answer (study prompts avoid assignment questions)", isOn: $course.teachDontAnswer)
                TextField("Sections", text: $sectionsText, prompt: Text("LEC 005, TUT 104"))
                Picker("Colour", selection: $course.colorIndex) {
                    ForEach(0..<Palette.courses.count, id: \.self) { index in
                        HStack { CourseDot(color: Palette.color(index), size: 10); Text("Colour \(index + 1)") }.tag(index)
                    }
                }
                LabeledContent("Folder", value: course.folderPath ?? "—")
            }
            .formStyle(.grouped)
        } actions: {
            Button("Delete Course…", role: .destructive) { confirmDelete = true }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") {
                var saved = course
                saved.code = CourseCode.normalize(course.code) ?? course.code.uppercased()
                saved.sections = sectionsText.split(separator: ",").map { String($0).trimmed.uppercased() }.filter { !$0.isEmpty }
                store.updateCourse(saved)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .confirmationDialog("Delete \(course.code)?", isPresented: $confirmDelete) {
            Button("Delete Course and Its Items", role: .destructive) { store.deleteCourse(course, removingItems: true); dismiss() }
            Button("Delete Course Only") { store.deleteCourse(course, removingItems: false); dismiss() }
        }
        .onAppear {
            if let existing = store.courses.first(where: { $0.id == courseID }) {
                course = existing
                sectionsText = existing.sections.joined(separator: ", ")
            }
        }
    }
}
