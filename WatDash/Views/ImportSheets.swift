//
//  ImportSheets.swift
//  WatDash
//

import SwiftUI

/// Shared chrome for import sheets: title, explanation, content, buttons.
struct SheetScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String
    var width: CGFloat = 640
    var height: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content()
            HStack { actions() }
        }
        .padding(22)
        .frame(width: width, height: height)
    }
}

// MARK: - Quest paste

struct QuestPasteSheet: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var meetings: [ParsedMeeting] = []

    var body: some View {
        SheetScaffold(
            title: "Paste your Quest schedule",
            subtitle: "In Quest: Academics → Enroll → My Class Schedule → List View. Select the whole page (⌘A), copy (⌘C) and paste it here. Tip: that page's “Download Schedule” button gives an .ics you can drop on WatDash instead.",
            height: 560
        ) {
            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 160)
                .onChange(of: text) { _, value in meetings = ImportService.shared.previewQuest(value) }
            if meetings.isEmpty {
                Text(text.isEmpty ? "Waiting for a paste…" : "No class rows recognised yet. Make sure the course headings (“MATH 137 - Calculus 1…”) are included.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                List(meetings) { meeting in
                    HStack {
                        Text(meeting.courseCode).font(.callout.weight(.semibold)).frame(width: 80, alignment: .leading)
                        Text(meeting.label).frame(width: 70, alignment: .leading)
                        Text(daysText(meeting.weekdays)).frame(width: 70, alignment: .leading)
                        Text("\(timeText(meeting.startMinutes))–\(timeText(meeting.endMinutes))")
                        Spacer()
                        Text(meeting.location ?? "").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .frame(minHeight: 140)
            }
        } actions: {
            Text(meetings.isEmpty ? "" : "\(meetings.count) meetings in \(Set(meetings.map(\.courseCode)).count) courses")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import") {
                let summary = ImportService.shared.importQuest(meetings)
                router.show("\(summary.title): \(summary.detail)")
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(meetings.isEmpty)
        }
    }
}

func daysText(_ weekdays: [Int]) -> String {
    let names = ["", "Su", "M", "T", "W", "Th", "F", "Sa"]
    return weekdays.sorted { RecurrenceExpander.mondayIndex($0) < RecurrenceExpander.mondayIndex($1) }.map { names[$0] }.joined()
}

func timeText(_ minutes: Int) -> String {
    let hour = minutes / 60, minute = minutes % 60
    let display = hour % 12 == 0 ? 12 : hour % 12
    return String(format: "%d:%02d %@", display, minute, hour < 12 ? "AM" : "PM")
}

// MARK: - Outline

struct OutlineImportSheet: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    var url: URL
    @State private var outline: ParsedOutline?
    @State private var error: String?
    @State private var chosen: Set<String> = []
    @State private var useScheme = true

    var body: some View {
        SheetScaffold(
            title: outline?.courseCode.map { "\($0) outline" } ?? "Course outline",
            subtitle: "Pick your own sections (from Quest) — the outline lists every section of the course. The assessment table becomes the grading scheme.",
            height: 560
        ) {
            if let error {
                Text(error).foregroundStyle(Palette.bad)
            } else if let outline {
                if let title = outline.courseTitle { Text(title).font(.headline) }
                List {
                    Section("Sections") {
                        ForEach(outline.meetings.filter { $0.component != "TST" }) { meeting in
                            Toggle(isOn: Binding(
                                get: { chosen.contains(meeting.label) },
                                set: { if $0 { chosen.insert(meeting.label) } else { chosen.remove(meeting.label) } }
                            )) {
                                HStack {
                                    Text(meeting.label).font(.callout.weight(.semibold)).frame(width: 70, alignment: .leading)
                                    Text(daysText(meeting.weekdays)).frame(width: 60, alignment: .leading)
                                    Text("\(timeText(meeting.startMinutes))–\(timeText(meeting.endMinutes))").frame(width: 150, alignment: .leading)
                                    Text(meeting.location ?? "").foregroundStyle(.secondary)
                                    Spacer()
                                    Text(meeting.instructor ?? "").foregroundStyle(.secondary).lineLimit(1)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    if !outline.assessments.isEmpty {
                        Section("Assessments") {
                            ForEach(outline.assessments, id: \.self) { row in
                                HStack {
                                    Text(row.component)
                                    Spacer()
                                    Text(row.dateText).foregroundStyle(.secondary)
                                    Text(row.weight.map { "\($0.noDecimals)%" } ?? "—").frame(width: 50, alignment: .trailing)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                Toggle("Use the assessment table as the grading scheme (if the course has none yet)", isOn: $useScheme)
            } else {
                ProgressView()
            }
        } actions: {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import") {
                guard let outline else { return }
                let summary = ImportService.shared.importOutline(outline, file: url, sections: chosen, useScheme: useScheme)
                router.show("\(summary.title): \(summary.detail)")
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(outline == nil)
        }
        .task {
            do {
                let parsed = try ImportService.shared.parseOutline(url)
                if parsed.courseCode == nil { error = "That page doesn't look like an outline.uwaterloo.ca outline." }
                outline = parsed
                if let code = parsed.courseCode, let course = AppStore.shared.course(code: code) {
                    chosen = Set(course.sections)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Course folders

struct CourseFolderSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [ImportService.FolderScan] = []
    @State private var included: Set<String> = []
    @State private var sections: [String: Set<String>] = [:]
    @State private var includeSelfStudy = false

    var body: some View {
        SheetScaffold(
            title: "Course folders",
            subtitle: "Each course folder's CLAUDE.md already holds its calendar, grading scheme, notes page map and study pages. Re-scanning updates dates and keeps your marks.",
            width: 720, height: 600
        ) {
            HStack {
                Image(systemName: "folder")
                Text(store.settings.classesFolderPath).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Change…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.directoryURL = URL(fileURLWithPath: store.settings.classesFolderPath)
                    if panel.runModal() == .OK, let url = panel.url {
                        var settings = store.settings
                        settings.classesFolderPath = url.path
                        store.settings = settings
                        rescan()
                    }
                }
            }
            .font(.callout)
            if scans.isEmpty {
                EmptyState(symbol: "folder.badge.questionmark", title: "No course folders found",
                           message: "WatDash looks for subfolders containing a CLAUDE.md with a heading like “# MATH 137: …”.")
            } else {
                List {
                    ForEach(scans) { scan in
                        folderRow(scan)
                    }
                }
            }
            if scans.contains(where: \.parsed.isSelfStudy) {
                Toggle("Include self-study courses (they never count toward your average)", isOn: $includeSelfStudy)
                    .font(.callout)
            }
        } actions: {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import \(included.count) Course\(included.count == 1 ? "" : "s")") {
                let chosen = scans.filter { included.contains($0.id) }
                let summary = ImportService.shared.importCourseFolders(chosen, sections: sections, includeSelfStudy: includeSelfStudy)
                if includeSelfStudy {
                    for scan in chosen where scan.parsed.isSelfStudy {
                        if var course = store.course(code: scan.parsed.code) { course.countsTowardAverage = false; store.updateCourse(course) }
                    }
                }
                router.show("\(summary.title): \(summary.detail)")
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(included.isEmpty)
        }
        .onAppear(perform: rescan)
    }

    private func rescan() {
        scans = ImportService.shared.scanCourseFolders()
        included = Set(scans.filter { !$0.parsed.isSelfStudy }.map(\.id))
        for scan in scans {
            if let code = scan.parsed.code, let course = store.course(code: code), !course.sections.isEmpty {
                sections[code] = Set(course.sections)
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ scan: ImportService.FolderScan) -> some View {
        let parsed = scan.parsed
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { included.contains(scan.id) },
                set: { if $0 { included.insert(scan.id) } else { included.remove(scan.id) } }
            )) {
                HStack {
                    Text(parsed.code ?? "?").font(.headline)
                    Text(parsed.title ?? "").foregroundStyle(.secondary)
                    if parsed.isSelfStudy { Text("self-study").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule()) }
                    if parsed.teachDontAnswer { Text("teach, don't answer").font(.caption2).padding(.horizontal, 5).background(Palette.accent.opacity(0.2), in: Capsule()) }
                }
            }
            HStack(spacing: 14) {
                stat("\(parsed.rows.filter { $0.due != nil }.count)/\(parsed.rows.count)", "dated assessments")
                stat(parsed.components.isEmpty ? (scan.outline?.assessments.isEmpty == false ? "outline" : "—") : "\(parsed.components.count)", "scheme parts")
                stat("\(parsed.pageMap.count)", "notes sections")
                stat("\(parsed.studyLinks.count + scan.localStudyPages.count)", "study pages")
                if !parsed.noClassRanges.isEmpty { stat("\(parsed.noClassRanges.count)", "no-class ranges") }
            }
            .padding(.leading, 20)
            if let outline = scan.outline, let code = parsed.code {
                let labels = outline.sectionLabels.filter { !$0.hasPrefix("TST") }
                HStack(alignment: .firstTextBaseline) {
                    Text("Your sections:").font(.caption).foregroundStyle(.secondary)
                    Menu(sections[code].map { $0.sorted().joined(separator: ", ") }.flatMap { $0.isEmpty ? nil : $0 } ?? "Pick from outline") {
                        ForEach(labels, id: \.self) { label in
                            Toggle(label, isOn: Binding(
                                get: { sections[code, default: []].contains(label) },
                                set: { on in
                                    var set = sections[code, default: []]
                                    if on {
                                        // One section per component (one LEC, one TUT).
                                        let component = label.split(separator: " ").first.map(String.init) ?? ""
                                        set = set.filter { !$0.hasPrefix(component + " ") }
                                        set.insert(label)
                                    } else { set.remove(label) }
                                    sections[code] = set
                                }
                            ))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.caption)
                    Text("adds class times from the saved outline").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feed

struct FeedSheet: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        SheetScaffold(
            title: "Subscribe to a calendar feed",
            subtitle: "Any iCalendar URL (webcal:// or https://). WatDash re-reads it on a timer, so upstream changes arrive on their own."
        ) {
            Form {
                TextField("Feed URL", text: $url, prompt: Text("webcal://… or https://…/basic.ics"))
                TextField("Name", text: $name, prompt: Text("e.g. LEARN calendar"))
            }
            .formStyle(.grouped)
            VStack(alignment: .leading, spacing: 6) {
                Label("LEARN: Calendar → Subscribe (if Waterloo has feeds switched on) gives every course's due dates.", systemImage: "graduationcap")
                Label("Course office hours in a public Google Calendar: the embed's calendar id goes into calendar.google.com/calendar/ical/<id>/public/basic.ics.", systemImage: "door.left.hand.open")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(Palette.bad).font(.callout) }
        } actions: {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button {
                busy = true
                error = nil
                Task {
                    do {
                        let summary = try await ImportService.shared.subscribe(to: url, name: name)
                        router.show("\(summary.title): \(summary.detail)")
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    busy = false
                }
            } label: {
                if busy { ProgressView().controlSize(.small) } else { Text("Subscribe") }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(url.trimmed.isEmpty || busy)
        }
    }
}

// MARK: - Apple Calendar

struct AppleCalendarSheet: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [CalendarSync.CalendarChoice] = []
    @State private var chosen: Set<String> = []
    @State private var needsAccess = false

    var body: some View {
        SheetScaffold(
            title: "Import from Apple Calendar",
            subtitle: "Pick calendars that already hold classes or events: Google, Outlook and iCloud accounts added in System Settings all appear here. WatDash re-reads them whenever they change.",
            height: 480
        ) {
            if needsAccess {
                EmptyState(symbol: "calendar.badge.exclamationmark", title: "Calendar access needed",
                           message: "WatDash reads only the calendars you pick.", actionTitle: "Allow Access") {
                    Task { await load(requesting: true) }
                }
            } else {
                List(calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(calendar.id) },
                        set: { if $0 { chosen.insert(calendar.id) } else { chosen.remove(calendar.id) } }
                    )) {
                        HStack {
                            CourseDot(color: Color(red: calendar.colorComponents[0], green: calendar.colorComponents[1], blue: calendar.colorComponents[2]), size: 10)
                            Text(calendar.title)
                            Spacer()
                            Text(calendar.sourceTitle).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import \(chosen.count)") {
                let names = calendars.filter { chosen.contains($0.id) }.map(\.title)
                ImportService.shared.addAppleCalendars(Array(chosen), name: names.joined(separator: ", "))
                router.show("Imported \(names.joined(separator: ", ")).")
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(chosen.isEmpty)
        }
        .task { await load(requesting: false) }
    }

    private func load(requesting: Bool) async {
        let sync = CalendarSync.shared
        if !sync.hasAccess {
            if requesting { _ = await sync.requestAccess() }
            if !sync.hasAccess { needsAccess = true; return }
        }
        needsAccess = false
        calendars = sync.availableCalendars()
    }
}

// MARK: - Open Data

struct OpenDataSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.get(.openData) ?? ""
    @State private var busy: String?
    @State private var log: [String] = []
    @State private var newWatchCourse = ""
    @State private var newWatchSection = ""
    @State private var campusEvents: [OpenDataClient.SiteEvent] = []

    var body: some View {
        SheetScaffold(
            title: "Waterloo Open Data",
            subtitle: "The university's official API: class times for your sections, important dates (drop deadlines, reading week), final exam slots, seat counts and campus events. Needs a free key registered with your email.",
            width: 720, height: 640
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SecureField("API key", text: $key)
                        Button("Save") {
                            Keychain.set(key, for: .openData)
                            log.insert("Key saved to your keychain.", at: 0)
                        }
                        Link("Get a key", destination: OpenDataClient.registrationPage)
                    }
                    HStack {
                        Text("Term").foregroundStyle(.secondary)
                        Text("\(store.settings.termName) (\(store.settings.termCode))")
                        Spacer()
                        Button("Use current term") { run("term") { try await currentTerm() } }
                    }
                    .font(.callout)

                    Divider()
                    Text("Import").font(.headline)
                    HStack {
                        Button("Class times for my sections") { run("classes") { try await ImportService.shared.importOpenDataClasses() } }
                        Button("Important dates") { run("dates") { try await ImportService.shared.importImportantDates() } }
                        Button("Final exams") { run("exams") { try await ImportService.shared.importExams() } }
                    }
                    Text("Class times need each course's sections (e.g. LEC 005, TUT 104): they come from a Quest import, or set them under Edit Course.")
                        .font(.caption).foregroundStyle(.secondary)

                    Divider()
                    Text("Seat watch").font(.headline)
                    ForEach(store.seatWatches) { watch in
                        HStack {
                            Text(watch.courseCode).font(.callout.weight(.semibold))
                            Text(watch.section.isEmpty ? "any LEC" : "section \(watch.section)").foregroundStyle(.secondary)
                            Spacer()
                            if let open = watch.openSeats { Text("\(open) open of \(watch.capacity ?? 0)") }
                            Button { store.setSeatWatches(store.seatWatches.filter { $0.id != watch.id }) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        .font(.callout)
                    }
                    HStack {
                        TextField("Course", text: $newWatchCourse, prompt: Text("RUSS 101"))
                        TextField("Section", text: $newWatchSection, prompt: Text("001 (optional)")).frame(width: 130)
                        Button("Watch") {
                            guard let code = CourseCode.normalize(newWatchCourse) else { return }
                            store.setSeatWatches(store.seatWatches + [SeatWatch(courseCode: code, section: newWatchSection.trimmed)])
                            newWatchCourse = ""
                            newWatchSection = ""
                            Task { await ImportService.shared.checkSeats() }
                        }
                        Button("Check now") { run("seats") { await ImportService.shared.checkSeats(); return .init(title: "Seats", detail: "Checked.") } }
                    }

                    Divider()
                    HStack {
                        Text("Campus events").font(.headline)
                        Spacer()
                        Button("Load latest") { run("events") { try await loadEvents() } }
                    }
                    ForEach(campusEvents) { event in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.title ?? "Event").font(.callout.weight(.medium))
                                Text([OpenDataClient.date(event.eventStartDate)?.formatted(date: .abbreviated, time: .shortened), event.locationName, event.host]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { add(event) }
                        }
                    }
                    ForEach(log, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } actions: {
            if let busy { ProgressView().controlSize(.small); Text("Working on \(busy)…").font(.caption) }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> ImportService.Summary) {
        if !key.isEmpty, Keychain.get(.openData) != key { Keychain.set(key, for: .openData) }
        busy = label
        Task {
            do {
                let summary = try await work()
                log.insert("\(summary.title): \(summary.detail)", at: 0)
            } catch {
                log.insert(error.localizedDescription, at: 0)
            }
            busy = nil
        }
    }

    private func currentTerm() async throws -> ImportService.Summary {
        let term = try await ImportService.shared.openData.currentTerm()
        var settings = store.settings
        if let code = term.termCode { settings.termCode = code }
        if let name = term.name { settings.termName = name }
        if let start = OpenDataClient.date(term.termBeginDate) { settings.termStart = start }
        if let end = OpenDataClient.date(term.termEndDate) { settings.termEnd = end }
        store.settings = settings
        return .init(title: "Term", detail: "\(settings.termName) (\(settings.termCode))")
    }

    private func loadEvents() async throws -> ImportService.Summary {
        let events = try await ImportService.shared.openData.latestEvents(40)
        campusEvents = events.filter { (OpenDataClient.date($0.eventStartDate) ?? .distantPast) > .now }
        return .init(title: "Campus events", detail: "\(campusEvents.count) upcoming")
    }

    private func add(_ event: OpenDataClient.SiteEvent) {
        guard let start = OpenDataClient.date(event.eventStartDate) else { return }
        let end = OpenDataClient.date(event.eventEndDate) ?? start.addingTimeInterval(3600)
        let source = store.sources.first { $0.kind == .openData } ?? store.addSource(DataSource(kind: .openData, name: "Waterloo Open Data"))
        store.addEvent(DashEvent(id: "\(source.id.uuidString):wcms:\(event.id)", title: event.title ?? "Event", kind: .event,
                                 start: start, end: max(end, start), location: event.locationName,
                                 url: event.eventWebsite ?? event.itemUri, timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id))
        router.show("Added \(event.title ?? "event").")
    }
}

// MARK: - Inbox

struct InboxSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: "Inbox", subtitle: "Captures WatDash wasn't confident about.", height: 420) {
            List(store.proposedEvents) { InboxRow(event: $0) }
        } actions: {
            Button("Add All") { store.acceptAllProposed() }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}
