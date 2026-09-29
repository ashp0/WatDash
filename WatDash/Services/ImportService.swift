//
//  ImportService.swift
//  WatDash
//

import Foundation

/// Every way data gets in, behind one object. Each importer turns its input
/// into store models and hands them to `AppStore.applyImport` under a source,
/// so every import is idempotent and removable.
@MainActor
final class ImportService {
    static let shared = ImportService()
    private var store: AppStore { AppStore.shared }
    private var refreshTimer: Timer?
    private(set) var isRefreshing = false

    struct Summary: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
        var isError = false
    }

    // MARK: - Calendar files and feeds

    func importICSFile(_ url: URL) throws -> Summary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try ICSParser.parse(text)
        let source = store.sources.first { $0.kind == .icsFile && $0.location == url.path }
            ?? store.addSource(DataSource(kind: .icsFile, name: url.deletingPathExtension().lastPathComponent, location: url.path))
        let events = ICSImport.events(from: parsed, sourceID: source.id, knownCourses: store.knownCourseCodes)
        createCourses(for: events)
        // Re-run classification now that the courses exist.
        let final = ICSImport.events(from: parsed, sourceID: source.id, knownCourses: store.knownCourseCodes)
        store.applyImport(sourceID: source.id, events: final)
        let classes = final.filter { $0.kind.isClassMeeting }.count
        return Summary(title: "Imported \(url.lastPathComponent)", detail: "\(final.count) events, \(classes) of them class meetings.")
    }

    @discardableResult
    func subscribe(to raw: String, name: String?) async throws -> Summary {
        guard let url = feedURL(raw) else { throw URLError(.badURL) }
        let source = store.sources.first { $0.kind == .icsFeed && $0.location == url.absoluteString }
            ?? store.addSource(DataSource(kind: .icsFeed, name: name?.nilIfEmpty ?? url.host() ?? "Calendar feed", location: url.absoluteString))
        let count = try await refreshFeed(source)
        return Summary(title: "Subscribed to \(source.name)", detail: "\(count) events. Refreshes every \(Int(store.settings.feedRefreshMinutes)) minutes.")
    }

    func feedURL(_ raw: String) -> URL? {
        var text = raw.trimmed
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
    }

    @discardableResult
    func refreshFeed(_ source: DataSource) async throws -> Int {
        guard let location = source.location, let url = URL(string: location) else { throw URLError(.badURL) }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned \(http.statusCode)"])
            }
            let text = String(decoding: data, as: UTF8.self)
            let parsed = try ICSParser.parse(text)
            var events = ICSImport.events(from: parsed, sourceID: source.id, knownCourses: store.knownCourseCodes)
            if source.kind == .holidays {
                let window = DateInterval(start: store.settings.termStart.addingTimeInterval(-60 * 86_400),
                                          end: store.settings.termEnd.addingTimeInterval(200 * 86_400))
                events = events.filter { window.contains($0.start) }.map { event in
                    var event = event
                    event.kind = .holiday
                    event.cancelsClasses = true
                    return event
                }
            }
            store.applyImport(sourceID: source.id, events: events)
            return events.count
        } catch {
            store.recordSourceError(source.id, error.localizedDescription)
            throw error
        }
    }

    /// UW paid holidays (Thanksgiving, Family Day, …), from the anonymous Open
    /// Data feed: they cancel class meetings automatically.
    func importHolidays() async throws -> Summary {
        let location = OpenDataClient.holidaysFeed.absoluteString
        let source = store.sources.first { $0.kind == .holidays }
            ?? store.addSource(DataSource(kind: .holidays, name: "UW holidays", location: location))
        let count = try await refreshFeed(source)
        return Summary(title: "UW holidays added", detail: "\(count) holidays this academic year. Classes on those days are cancelled.")
    }

    // MARK: - Quest paste

    func previewQuest(_ text: String) -> [ParsedMeeting] {
        QuestScheduleParser.parse(text, year: Waterloo.calendar.component(.year, from: store.settings.termStart))
    }

    func importQuest(_ meetings: [ParsedMeeting]) -> Summary {
        let source = store.sources.first { $0.kind == .questPaste }
            ?? store.addSource(DataSource(kind: .questPaste, name: "Quest class schedule"))
        for meeting in meetings { store.ensureCourse(code: meeting.courseCode, title: meeting.courseTitle) }
        let events = meetings.compactMap {
            $0.event(sourceID: source.id, fallbackStart: store.settings.termStart, fallbackEnd: store.settings.termEnd)
        }
        store.applyImport(sourceID: source.id, events: events)
        rememberSections(meetings)
        let courses = Set(meetings.map(\.courseCode)).count
        return Summary(title: "Quest schedule imported", detail: "\(events.count) meeting patterns across \(courses) courses.")
    }

    private func rememberSections(_ meetings: [ParsedMeeting]) {
        for code in Set(meetings.map(\.courseCode)) {
            guard var course = store.course(code: code) else { continue }
            let labels = meetings.filter { $0.courseCode == code }.map(\.label).filter { !$0.isEmpty }
            course.sections = Array(Set(course.sections + labels)).sorted()
            store.updateCourse(course)
        }
    }

    // MARK: - Course outline (outline.uwaterloo.ca saved page)

    func parseOutline(_ url: URL) throws -> ParsedOutline {
        // A file picked on iOS is only readable while its scope is open.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let html = try String(contentsOf: url, encoding: .utf8)
        return OutlineParser.parse(html: html, year: Waterloo.calendar.component(.year, from: store.settings.termStart))
    }

    func importOutline(_ outline: ParsedOutline, file: URL, sections: Set<String>, useScheme: Bool) -> Summary {
        guard let code = outline.courseCode else {
            return Summary(title: "No course found", detail: "That page doesn't look like an outline.uwaterloo.ca outline.", isError: true)
        }
        let source = store.sources.first { $0.kind == .outline && $0.location == file.path }
            ?? store.addSource(DataSource(kind: .outline, name: "\(code) outline", location: file.path))
        var course = store.ensureCourse(code: code, title: outline.courseTitle)
        if useScheme, !outline.assessments.isEmpty {
            let scheme = OutlineParser.scheme(from: outline.assessments)
            if course.scheme.components.isEmpty || course.scheme.totalWeight == 0 {
                course.scheme = scheme
            }
        }
        course.sections = Array(Set(course.sections).union(sections)).sorted()
        store.updateCourse(course)
        let chosen = outline.meetings.filter { sections.contains($0.label) || $0.component == "TST" }
        let events = chosen.compactMap {
            $0.event(sourceID: source.id, fallbackStart: store.settings.termStart, fallbackEnd: store.settings.termEnd)
        }.filter { $0.kind != .test }  // test slots come in as assessments via the course folder or by hand
        store.applyImport(sourceID: source.id, events: events)
        return Summary(title: "\(code) outline imported", detail: "\(events.count) meeting patterns\(useScheme ? " and the grading scheme" : "").")
    }

    // MARK: - Course folders (CLAUDE.md)

    struct FolderScan: Identifiable {
        var id: String { folder.path }
        var folder: URL
        var parsed: ParsedCourseFolder
        var outline: ParsedOutline?
        var outlineFile: URL?
        var localStudyPages: [URL]
        var pdfs: [String]
    }

    /// Runs `body` with the classes folder readable. On the Mac that's just
    /// its path; on iOS it's the folder picked in Files, opened through its
    /// bookmark (anything inside it is readable while the scope is open).
    func withClassesFolder<T>(_ body: (URL) -> T) -> T {
        #if os(macOS)
        return body(URL(fileURLWithPath: store.settings.classesFolderPath))
        #else
        var stale = false
        guard let bookmark = store.settings.classesFolderBookmark,
              let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return body(Self.onDeviceClassesFolder) }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData() {
            var settings = store.settings
            settings.classesFolderBookmark = fresh
            store.settings = settings
        }
        return body(url)
        #endif
    }

    #if !os(macOS)
    /// Without a picked folder, iOS looks in the app's own Documents (On My
    /// iPhone › WatDash in Files). Worked out each time: the app container's
    /// path changes when the app is reinstalled or updated, so a saved
    /// absolute path would go stale.
    static var onDeviceClassesFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("University of Waterloo Classes", isDirectory: true)
    }
    #endif

    /// The classes folder as Settings shows it: the path on the Mac, the
    /// folder's name on iOS, where paths mean nothing to a person.
    var classesFolderName: String {
        #if os(macOS)
        store.settings.classesFolderPath
        #else
        store.settings.classesFolderBookmark == nil
            ? "On My iPhone › WatDash › \(Self.onDeviceClassesFolder.lastPathComponent)"
            : URL(fileURLWithPath: store.settings.classesFolderPath).lastPathComponent
        #endif
    }

    /// Remembers a classes folder chosen in a picker. On iOS the picked URL
    /// is only good for this session, so a bookmark is kept too.
    func setClassesFolder(_ url: URL) {
        var settings = store.settings
        settings.classesFolderPath = url.path
        #if !os(macOS)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        settings.classesFolderBookmark = try? url.bookmarkData()
        #endif
        store.settings = settings
    }

    func scanCourseFolders(root: URL? = nil) -> [FolderScan] {
        withClassesFolder { classes in scan(root ?? classes) }
    }

    private func scan(_ rootURL: URL) -> [FolderScan] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        let year = Waterloo.calendar.component(.year, from: store.settings.termStart)
        var scans: [FolderScan] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifest = folder.appendingPathComponent("CLAUDE.md")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            let parsed = CourseFolderParser.parse(markdown: text, fallbackYear: year)
            guard parsed.code != nil else { continue }

            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            var outline: ParsedOutline?
            var outlineFile: URL?
            for file in files where file.pathExtension.lowercased() == "html" {
                guard let html = try? String(contentsOf: file, encoding: .utf8), html.contains("schedule-info") || html.contains("outline-content") else { continue }
                outline = OutlineParser.parse(html: html, year: year)
                outlineFile = file
                break
            }
            let study = folder.appendingPathComponent("study")
            let pages = ((try? fm.contentsOfDirectory(at: study, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "html" && !$0.lastPathComponent.hasSuffix(".src.html") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }.map(\.lastPathComponent).sorted()
            scans.append(FolderScan(folder: folder, parsed: parsed, outline: outline, outlineFile: outlineFile, localStudyPages: pages, pdfs: pdfs))
        }
        return scans
    }

    /// `sections` maps course code → chosen outline sections ("LEC 005").
    func importCourseFolders(_ scans: [FolderScan], sections: [String: Set<String>] = [:], includeSelfStudy: Bool = false) -> Summary {
        var assessmentCount = 0
        var eventCount = 0
        var courseCount = 0
        for scan in scans {
            guard let code = scan.parsed.code else { continue }
            if scan.parsed.isSelfStudy && !includeSelfStudy { continue }
            courseCount += 1
            let source = store.sources.first { $0.kind == .courseFolder && $0.location == scan.folder.path }
                ?? store.addSource(DataSource(kind: .courseFolder, name: "\(code) folder", location: scan.folder.path))

            var course = store.ensureCourse(code: code, title: scan.parsed.title ?? scan.outline?.courseTitle)
            course.folderPath = scan.folder.path
            if let notes = scan.parsed.notesFile { course.notesFile = notes }
            if !scan.parsed.pageMap.isEmpty { course.pageMap = scan.parsed.pageMap }
            course.teachDontAnswer = scan.parsed.teachDontAnswer
            if let accent = scan.parsed.accentIndex { course.colorIndex = accent }
            if course.scheme.components.isEmpty {
                if !scan.parsed.components.isEmpty {
                    course.scheme.components = scan.parsed.components
                } else if let outline = scan.outline, !outline.assessments.isEmpty {
                    course.scheme = OutlineParser.scheme(from: outline.assessments)
                }
            }
            var links = scan.parsed.studyLinks
            links += scan.localStudyPages.map { StudyLink(title: $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized, url: $0.path, note: "Local build") }
            for link in links where !course.studyLinks.contains(where: { $0.url == link.url }) {
                course.studyLinks.append(link)
            }
            if let chosen = sections[code] { course.sections = Array(chosen).sorted() }
            store.updateCourse(course)

            let assessments: [Assessment] = scan.parsed.rows.map { row in
                Assessment(
                    courseCode: code, title: row.title, kind: row.kind,
                    componentID: course.scheme.guessComponent(kind: row.kind, title: row.title)?.id,
                    due: row.due, end: row.end, coverage: row.coverage, location: row.location,
                    score: row.score, outOf: row.outOf ?? 100, isDone: row.isDone,
                    sourceKey: "\(code):\(row.title)", sourceID: source.id
                )
            }
            assessmentCount += assessments.count

            var events: [DashEvent] = scan.parsed.noClassRanges.map { range in
                let calendar = Waterloo.calendar
                let end = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end
                let stamp = Int(range.start.timeIntervalSince1970)
                return DashEvent(id: "noclass:\(stamp)", title: range.label, kind: .holiday, start: range.start, end: end,
                                 isAllDay: true, timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id, cancelsClasses: true)
            }
            if let outline = scan.outline {
                let chosen = Set(course.sections)
                events += outline.meetings
                    .filter { chosen.contains($0.label) && $0.component != "TST" }
                    .compactMap { $0.event(sourceID: source.id, fallbackStart: store.settings.termStart, fallbackEnd: store.settings.termEnd) }
            }
            events += CourseFolderParser.officeHourEvents(scan.parsed.officeHours, code: code,
                                                          termStart: store.settings.termStart, sourceID: source.id)
            eventCount += events.count
            store.applyImport(sourceID: source.id, events: events, assessments: assessments)
        }
        return Summary(title: "Course folders imported",
                       detail: "\(courseCount) courses, \(assessmentCount) assessments, \(eventCount) timetable entries.")
    }

    // MARK: - Apple Calendar

    func addAppleCalendars(_ ids: [String], name: String) {
        let source = store.addSource(DataSource(kind: .appleCalendar, name: name, calendarIdentifiers: ids))
        CalendarSync.shared.importEvents(source: source, into: store)
    }

    // MARK: - Open Data

    var openData: OpenDataClient { OpenDataClient(apiKey: Keychain.get(.openData)) }

    /// Pulls meeting times for each course's chosen sections.
    func importOpenDataClasses() async throws -> Summary {
        let client = openData
        let term = store.settings.termCode
        let source = store.sources.first { $0.kind == .openData }
            ?? store.addSource(DataSource(kind: .openData, name: "Waterloo Open Data", location: term))
        var events: [DashEvent] = []
        var missing: [String] = []
        for course in store.courses {
            let sections = await Self.fetchSections(client, term: term, course: course)
            let wanted = Set(course.sections.map { $0.uppercased() })
            let chosen = sections.filter { section in
                wanted.isEmpty ? false : wanted.contains("\(section.courseComponent ?? "") \(section.sectionLabel)".uppercased())
            }
            if chosen.isEmpty { missing.append(course.code); continue }
            for section in chosen {
                events += OpenDataClient.meetings(for: section, courseCode: course.code).compactMap {
                    $0.event(sourceID: source.id, fallbackStart: store.settings.termStart, fallbackEnd: store.settings.termEnd)
                }
            }
        }
        // Keep important dates this source already produced.
        let keep = store.events.filter { $0.sourceID == source.id && $0.id.contains(":date:") }
        store.applyImport(sourceID: source.id, events: events + keep)
        let note = missing.isEmpty ? "" : " Pick sections for \(missing.joined(separator: ", ")) to include them."
        return Summary(title: "Class times from Open Data", detail: "\(events.count) meeting patterns.\(note)")
    }

    private static func fetchSections(_ client: OpenDataClient, term: String, course: Course) async -> [OpenDataClient.ClassSection] {
        (try? await client.classes(term: term, subject: course.subject, catalog: course.catalogNumber)) ?? []
    }

    func importImportantDates() async throws -> Summary {
        let client = openData
        let source = store.sources.first { $0.kind == .openData }
            ?? store.addSource(DataSource(kind: .openData, name: "Waterloo Open Data", location: store.settings.termCode))
        let dates = try await client.importantDates()
        let term = store.settings.termName.lowercased()
        var events: [DashEvent] = []
        for item in dates {
            for detail in item.details ?? [] where (detail.termName ?? "").lowercased() == term {
                guard let start = OpenDataClient.date(detail.startDate) else { continue }
                let end = OpenDataClient.date(detail.endDate) ?? start
                let name = item.name ?? "Important date"
                let lower = name.lowercased()
                let noClasses = lower.contains("reading week") || lower.contains("no classes") || lower.contains("holiday") || lower.contains("study day")
                let calendar = Waterloo.calendar
                events.append(DashEvent(
                    id: "\(source.id.uuidString):date:\(DeterministicID.digest(name + (detail.startDate ?? "")))",
                    title: name, kind: noClasses ? .holiday : .deadline,
                    start: calendar.startOfDay(for: start),
                    end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end,
                    isAllDay: true, notes: item.description?.replacingMatches(#"<[^>]+>"#, with: "").trimmed.nilIfEmpty,
                    timeZoneID: Waterloo.timeZone.identifier, sourceID: source.id, cancelsClasses: noClasses
                ))
            }
        }
        let keep = store.events.filter { $0.sourceID == source.id && !$0.id.contains(":date:") }
        store.applyImport(sourceID: source.id, events: keep + events)
        return Summary(title: "Important dates added", detail: "\(events.count) dates for \(store.settings.termName): add/drop deadlines, reading week, exam period.")
    }

    /// Final exam slots for your courses, as TBA finals get their dates.
    func importExams() async throws -> Summary {
        let exams = try await openData.exams(term: store.settings.termCode)
        var updated = 0
        for course in store.courses {
            guard let exam = exams.first(where: { ($0.examDisplayName ?? "").uppercased().replacingOccurrences(of: " ", with: "") == course.code.replacingOccurrences(of: " ", with: "") }),
                  let day = OpenDataClient.date(exam.examWindowStartDate) else { continue }
            var start = day
            if let time = exam.examWindowStartTime, let minutes = MeetingText.minutes(from: time.replacingOccurrences(of: " ", with: "")) {
                start = Waterloo.calendar.date(byAdding: .minute, value: minutes, to: Waterloo.calendar.startOfDay(for: day)) ?? day
            }
            let duration = exam.examDuration.flatMap { Double($0.filter(\.isNumber)) }.map { $0 * 60 } ?? 150 * 60
            if var final = store.assessments.first(where: { $0.courseCode == course.code && $0.kind == .exam }) {
                final.due = start
                final.end = start.addingTimeInterval(duration)
                final.location = exam.location ?? final.location
                store.updateAssessment(final)
            } else {
                store.addAssessment(Assessment(courseCode: course.code, title: "Final exam", kind: .exam, due: start,
                                               end: start.addingTimeInterval(duration), location: exam.location))
            }
            updated += 1
        }
        return Summary(title: "Final exams", detail: updated == 0 ? "The Registrar hasn't posted your exams yet." : "\(updated) exam\(updated == 1 ? "" : "s") dated.")
    }

    /// Polls seat counts; notifies once when a watched section opens up.
    func checkSeats() async {
        guard Keychain.get(.openData) != nil, !store.seatWatches.isEmpty else { return }
        var watches = store.seatWatches
        for index in watches.indices {
            let watch = watches[index]
            let parts = watch.courseCode.split(separator: " ").map(String.init)
            guard parts.count == 2,
                  let sections = try? await openData.classes(term: store.settings.termCode, subject: parts[0], catalog: parts[1]) else { continue }
            let matching = sections.filter { section in
                watch.section.isEmpty ? section.courseComponent == "LEC" : section.sectionLabel == watch.section
            }
            let capacity = matching.compactMap(\.maxEnrollmentCapacity).reduce(0, +)
            let enrolled = matching.compactMap(\.enrolledStudents).reduce(0, +)
            watches[index].capacity = capacity
            watches[index].enrolled = enrolled
            watches[index].lastChecked = .now
            let open = capacity > enrolled
            if open && !watch.lastNotifiedOpen {
                NotificationScheduler.shared.notifyNow(title: "Seat open in \(watch.courseCode)",
                                                       body: "\(capacity - enrolled) of \(capacity) seats free\(watch.section.isEmpty ? "" : " in section \(watch.section)").")
            }
            watches[index].lastNotifiedOpen = open
        }
        store.setSeatWatches(watches)
    }

    // MARK: - Quick capture

    /// Adds a parsed capture. Confident, dated captures go straight in; the
    /// rest land in the inbox as proposals.
    @discardableResult
    func add(_ capture: CaptureResult, forceConfirm: Bool = false) -> String {
        let source = store.sources.first { $0.kind == .quickCapture }
            ?? store.addSource(DataSource(kind: .quickCapture, name: "Quick capture"))
        if capture.isAssessment, let code = capture.courseCode, let due = capture.start {
            store.addAssessment(Assessment(courseCode: code, title: capture.title, kind: capture.kind, due: due,
                                           end: capture.end, location: capture.location, sourceID: source.id))
            return "Added \(code) \(capture.title) — \(due.dayMonth), \(due.shortTime)"
        }
        guard let start = capture.start else {
            return "Couldn't find a date in that. Try “tue 2pm” or “oct 19”."
        }
        let proposed = !forceConfirm && capture.confidence < 0.45
        store.addEvent(DashEvent(
            id: "\(source.id.uuidString):\(UUID().uuidString)",
            title: capture.title, courseCode: capture.courseCode, kind: capture.kind,
            start: start, end: capture.end ?? start.addingTimeInterval(3600), isAllDay: capture.isAllDay,
            location: capture.location, recurrence: capture.recurrence,
            timeZoneID: TimeZone.current.identifier, sourceID: source.id,
            status: proposed ? .proposed : .confirmed
        ))
        return proposed ? "Saved to the inbox to confirm: \(capture.title)" : "Added \(capture.title) — \(start.dayMonth), \(start.shortTime)"
    }

    // MARK: - Refresh loop

    func startRefreshing() {
        refreshTimer?.invalidate()
        let interval = max(15, store.settings.feedRefreshMinutes) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await ImportService.shared.refreshAll() }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for source in store.sources where source.isEnabled {
            switch source.kind {
            case .icsFeed, .holidays:
                _ = try? await refreshFeed(source)
            case .appleCalendar:
                CalendarSync.shared.importEvents(source: source, into: store)
            case .courseFolder:
                if let path = source.location {
                    let folder = URL(fileURLWithPath: path)
                    let scans = scanCourseFolders(root: folder.deletingLastPathComponent()).filter { $0.folder.path == folder.path }
                    if !scans.isEmpty { _ = importCourseFolders(scans, includeSelfStudy: true) }
                }
            default:
                break
            }
        }
        await checkSeats()
    }

    // MARK: - Helpers

    private func createCourses(for events: [DashEvent]) {
        let codes = Set(events.filter { $0.kind.isClassMeeting }.compactMap { event -> String? in
            event.courseCode ?? CourseCode.normalize(event.title)
        })
        for code in codes { store.ensureCourse(code: code) }
    }
}
