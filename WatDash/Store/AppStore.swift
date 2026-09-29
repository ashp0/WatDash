//
//  AppStore.swift
//  WatDash
//

import Foundation
import Observation
import SwiftUI

/// The canonical store: one observable object holding every course, event,
/// assessment and source, persisted as a single JSON file.
///
/// Every view, the menu bar extra, the quick-capture panel and the App Intents
/// read the same instance. Every mutation funnels through `commit`, which saves
/// (debounced) and fans out to the projections — widgets, notifications, Apple
/// Calendar — so none of them can drift out of date.
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore(demo: ProcessInfo.processInfo.arguments.contains("-WatDashDemo"), fileName: AppStore.debugFileName)

    /// Debug builds can point at a scratch data file (-WatDashStore name) so
    /// end-to-end runs never touch the real store.
    private static var debugFileName: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-WatDashStore"), index + 1 < arguments.count {
            return "watdash-\(arguments[index + 1]).json"
        }
        #endif
        return nil
    }

    private(set) var data: AppData
    /// Ticks every 30 seconds so countdowns and "now" markers stay live.
    private(set) var now: Date = .now
    private(set) var term: GradeEngine.TermResult
    private(set) var lastSaveError: String?

    let isDemo: Bool
    let fileURL: URL

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var effectsTask: Task<Void, Never>?
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored var effects: [(AppStore) -> Void] = []

    init(demo: Bool, fileName: String? = nil) {
        isDemo = demo
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent(fileName ?? (demo ? "watdash-demo.json" : "watdash.json"))

        var loaded = AppData()
        if let raw = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(AppData.self, from: raw) {
                loaded = decoded
            } else {
                // Never silently overwrite a file we couldn't read.
                let quarantine = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: quarantine)
                Log.store.error("Couldn't decode the data file; kept a copy at \(quarantine.path, privacy: .public)")
            }
        }
        data = loaded
        term = GradeEngine.evaluateTerm([], parameters: .init())
        recomputeGrades()

        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = .now
    }

    // MARK: - Convenience accessors

    var settings: AppSettings {
        get { data.settings }
        set {
            // Observation fires on every write, equal or not; bindings (the
            // menu bar's isInserted, toggles) re-set identical values, and an
            // unguarded write here re-renders every scene in a loop.
            guard newValue != data.settings else { return }
            let gradesChanged = newValue.targetAverage != data.settings.targetAverage
                || newValue.examGap != data.settings.examGap
                || newValue.learnExamGap != data.settings.learnExamGap
                || newValue.roundCourseGrades != data.settings.roundCourseGrades
                || newValue.previousUnits != data.settings.previousUnits
                || newValue.previousAverage != data.settings.previousAverage
            data.settings = newValue
            commit(grades: gradesChanged)
        }
    }

    var courses: [Course] { data.courses }
    var events: [DashEvent] { data.events }
    var assessments: [Assessment] { data.assessments }
    var sources: [DataSource] { data.sources }
    var seatWatches: [SeatWatch] { data.seatWatches }

    var knownCourseCodes: [String] { data.courses.map(\.code) }

    var termWindow: DateInterval {
        DateInterval(start: data.settings.termStart, end: max(data.settings.termEnd, data.settings.termStart))
    }

    func course(code: String?) -> Course? {
        guard let code else { return nil }
        return data.courses.first { $0.code == code }
    }

    func colorIndex(for code: String?) -> Int? { course(code: code)?.colorIndex }

    func color(for code: String?) -> Color {
        guard let index = colorIndex(for: code) else { return .gray }
        return Palette.color(index)
    }

    func event(id: String) -> DashEvent? { data.events.first { $0.id == id } }
    func assessment(id: UUID) -> Assessment? { data.assessments.first { $0.id == id } }
    func source(id: UUID?) -> DataSource? { id.flatMap { id in data.sources.first { $0.id == id } } }

    var proposedEvents: [DashEvent] { data.events.filter { $0.status == .proposed } }

    // MARK: - Agenda queries

    func agenda(in window: DateInterval) -> [AgendaItem] {
        RecurrenceExpander.agenda(
            events: data.events.filter { $0.status == .confirmed },
            assessments: data.assessments,
            in: window
        )
    }

    func agenda(on day: Date) -> [AgendaItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return agenda(in: DateInterval(start: start, end: end))
    }

    /// Class currently in session and the next thing on the timetable.
    func nowAndNext() -> (current: AgendaItem?, next: AgendaItem?) {
        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), duration: 8 * 86_400)
        let items = agenda(in: window).filter { !$0.isAllDay }
        let current = items.first { !$0.isDue && $0.contains(now) }
        let next = items.first { $0.start > now }
        return (current, next)
    }

    /// Marked work and deadlines still ahead, soonest first.
    func upcomingDeadlines(days: Int = 14, includeDone: Bool = false) -> [AgendaItem] {
        let window = DateInterval(start: Calendar.current.startOfDay(for: now), duration: Double(days) * 86_400)
        return agenda(in: window).filter { item in
            (item.kind.isAssessment || item.kind.isDue) && (includeDone || !item.isDone) && item.end >= now
        }
    }

    var undatedAssessments: [Assessment] {
        data.assessments.filter { $0.due == nil && !$0.isGraded }
    }

    /// Next midterm or exam, for the countdown card.
    func nextExam() -> AgendaItem? {
        let window = DateInterval(start: now, duration: 150 * 86_400)
        return agenda(in: window).first { ($0.kind == .test || $0.kind == .exam) && $0.start > now }
    }

    // MARK: - Courses

    @discardableResult
    func ensureCourse(code: String, title: String? = nil) -> Course {
        if let index = data.courses.firstIndex(where: { $0.code == code }) {
            if let title, data.courses[index].title.isEmpty {
                data.courses[index].title = title
                commit()
            }
            return data.courses[index]
        }
        let used = Set(data.courses.map(\.colorIndex))
        let color = (0..<Palette.courses.count).first { !used.contains($0) } ?? data.courses.count
        let course = Course(code: code, title: title ?? "", colorIndex: color)
        data.courses.append(course)
        data.courses.sort { $0.code < $1.code }
        commit(grades: true)
        return course
    }

    func updateCourse(_ course: Course) {
        guard let index = data.courses.firstIndex(where: { $0.id == course.id }), data.courses[index] != course else { return }
        let oldCode = data.courses[index].code
        data.courses[index] = course
        if oldCode != course.code {
            for i in data.events.indices where data.events[i].courseCode == oldCode { data.events[i].courseCode = course.code }
            for i in data.assessments.indices where data.assessments[i].courseCode == oldCode { data.assessments[i].courseCode = course.code }
        }
        commit(grades: true)
    }

    func deleteCourse(_ course: Course, removingItems: Bool) {
        data.courses.removeAll { $0.id == course.id }
        if removingItems {
            data.events.removeAll { $0.courseCode == course.code }
            data.assessments.removeAll { $0.courseCode == course.code }
        }
        commit(grades: true)
    }

    // MARK: - Events

    func addEvent(_ event: DashEvent) {
        data.events.removeAll { $0.id == event.id }
        data.events.append(event)
        if let code = event.courseCode, course(code: code) == nil, event.kind.isClassMeeting {
            ensureCourse(code: code)
        }
        commit()
    }

    func updateEvent(_ event: DashEvent) {
        guard let index = data.events.firstIndex(where: { $0.id == event.id }) else { return addEvent(event) }
        guard data.events[index] != event else { return }
        data.events[index] = event
        commit()
    }

    func deleteEvent(id: String) {
        data.events.removeAll { $0.id == id }
        commit()
    }

    /// Removes one occurrence of a recurring event (a cancelled lecture).
    func skipOccurrence(eventID: String, at start: Date) {
        guard let index = data.events.firstIndex(where: { $0.id == eventID }) else { return }
        if data.events[index].recurrence == nil {
            data.events[index].status = .cancelled
        } else {
            data.events[index].exceptionDates.append(start)
        }
        commit()
    }

    func accept(proposed id: String) {
        guard let index = data.events.firstIndex(where: { $0.id == id }) else { return }
        data.events[index].status = .confirmed
        commit()
    }

    func acceptAllProposed() {
        for index in data.events.indices where data.events[index].status == .proposed {
            data.events[index].status = .confirmed
        }
        commit()
    }

    // MARK: - Assessments

    func addAssessment(_ assessment: Assessment) {
        var assessment = assessment
        if assessment.componentID == nil, let course = course(code: assessment.courseCode) {
            assessment.componentID = course.scheme.guessComponent(kind: assessment.kind, title: assessment.title)?.id
        }
        if course(code: assessment.courseCode) == nil { ensureCourse(code: assessment.courseCode) }
        data.assessments.append(assessment)
        commit(grades: true)
    }

    func updateAssessment(_ assessment: Assessment) {
        guard let index = data.assessments.firstIndex(where: { $0.id == assessment.id }) else { return addAssessment(assessment) }
        guard data.assessments[index] != assessment else { return }
        data.assessments[index] = assessment
        commit(grades: true)
    }

    func deleteAssessment(id: UUID) {
        data.assessments.removeAll { $0.id == id }
        commit(grades: true)
    }

    func toggleDone(_ item: AgendaItem) {
        switch item.origin {
        case let .assessment(id):
            guard let index = data.assessments.firstIndex(where: { $0.id == id }) else { return }
            data.assessments[index].isDone.toggle()
            commit()
        case .event:
            break
        }
    }

    /// Sets many what-if values at once (the what-if panel's sliders).
    func setWhatIf(_ values: [UUID: Double?]) {
        for (id, value) in values {
            guard let index = data.assessments.firstIndex(where: { $0.id == id }) else { continue }
            data.assessments[index].whatIf = value
        }
        commit(grades: true)
    }

    // MARK: - Sources and imports

    @discardableResult
    func addSource(_ source: DataSource) -> DataSource {
        data.sources.removeAll { $0.id == source.id }
        data.sources.append(source)
        commit()
        return source
    }

    func updateSource(_ source: DataSource) {
        guard let index = data.sources.firstIndex(where: { $0.id == source.id }), data.sources[index] != source else { return }
        data.sources[index] = source
        commit()
    }

    func removeSource(_ source: DataSource, removingItems: Bool) {
        data.sources.removeAll { $0.id == source.id }
        if removingItems {
            data.events.removeAll { $0.sourceID == source.id }
            data.assessments.removeAll { $0.sourceID == source.id && !$0.isGraded }
        }
        commit(grades: true)
    }

    /// Idempotent import: replaces whatever `sourceID` produced last time with
    /// `events`, keeping the user's own edits to surviving events (hidden,
    /// status). Assessments are matched on `sourceKey` so a re-scan updates
    /// dates without touching scores.
    func applyImport(sourceID: UUID, events: [DashEvent], assessments: [Assessment]? = nil, markRefreshed: Bool = true) {
        // Ids are stable across sources too ("reading week" arrives from every
        // course folder), so an incoming id replaces whoever owned it before.
        let incomingIDs = Set(events.map(\.id))
        let previous = Dictionary(data.events.filter { $0.sourceID == sourceID || incomingIDs.contains($0.id) }.map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        data.events.removeAll { $0.sourceID == sourceID || incomingIDs.contains($0.id) }
        for var event in events {
            if let old = previous[event.id] {
                event.isHidden = old.isHidden
                if old.status == .confirmed && event.status == .proposed { event.status = .confirmed }
                event.createdAt = old.createdAt
                // Keep occurrences the user skipped by hand.
                event.exceptionDates = Array(Set(event.exceptionDates + old.exceptionDates))
            }
            data.events.append(event)
        }

        if let assessments {
            for incoming in assessments {
                if let key = incoming.sourceKey, let index = data.assessments.firstIndex(where: { $0.sourceKey == key }) {
                    var merged = data.assessments[index]
                    merged.title = incoming.title
                    merged.kind = incoming.kind
                    merged.due = incoming.due ?? merged.due
                    merged.end = incoming.end ?? merged.end
                    merged.coverage = incoming.coverage ?? merged.coverage
                    merged.location = incoming.location ?? merged.location
                    if merged.componentID == nil { merged.componentID = incoming.componentID }
                    data.assessments[index] = merged
                } else {
                    var fresh = incoming
                    if fresh.componentID == nil, let course = course(code: fresh.courseCode) {
                        fresh.componentID = course.scheme.guessComponent(kind: fresh.kind, title: fresh.title)?.id
                    }
                    data.assessments.append(fresh)
                }
            }
        }

        if let index = data.sources.firstIndex(where: { $0.id == sourceID }) {
            if markRefreshed { data.sources[index].lastRefresh = .now }
            data.sources[index].lastError = nil
            data.sources[index].itemCount = events.count + (assessments?.count ?? 0)
        }
        commit(grades: assessments != nil)
    }

    func recordSourceError(_ sourceID: UUID, _ message: String) {
        guard let index = data.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        data.sources[index].lastError = message
        commit()
    }

    func setSeatWatches(_ watches: [SeatWatch]) {
        data.seatWatches = watches
        commit()
    }

    func replaceAll(with newData: AppData) {
        data = newData
        commit(grades: true)
    }

    // MARK: - Grades

    var gradeParameters: GradeEngine.Parameters {
        var parameters = GradeEngine.Parameters()
        parameters.target = data.settings.targetAverage
        parameters.examGap = effectiveExamGap
        parameters.roundCourseGrades = data.settings.roundCourseGrades
        return parameters
    }

    /// Your own history beats the prior once there's any: learned gap when
    /// enabled and available, clamped to something sane.
    var effectiveExamGap: Double {
        guard data.settings.learnExamGap, let learned = GradeEngine.learnedExamGap(gradeInputs) else {
            return data.settings.examGap
        }
        return min(25, max(-5, learned))
    }

    var gradeInputs: [GradeEngine.CourseInput] {
        data.courses.filter(\.countsTowardAverage).map { GradeEngine.input(for: $0, assessments: data.assessments) }
    }

    func courseResult(_ code: String) -> GradeEngine.CourseResult? {
        term.courses.first { $0.code == code }
    }

    func recomputeGrades() {
        term = GradeEngine.evaluateTerm(
            gradeInputs,
            parameters: gradeParameters,
            previousUnits: data.settings.previousUnits,
            previousAverage: data.settings.previousAverage
        )
    }

    // MARK: - Commit

    /// Every mutation ends here.
    func commit(grades: Bool = false) {
        if grades { recomputeGrades() }
        scheduleSave()
        scheduleEffects()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let raw = try encoder.encode(data)
            // One rolling daily backup: cheap insurance against a bad import.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
            let attributes = try? FileManager.default.attributesOfItem(atPath: backup.path)
            let backupDate = attributes?[.modificationDate] as? Date ?? .distantPast
            if Date.now.timeIntervalSince(backupDate) > 86_400, FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            try raw.write(to: fileURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            Log.store.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleEffects() {
        effectsTask?.cancel()
        effectsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            for effect in self.effects { effect(self) }
        }
    }

    /// Runs projections immediately (used on launch and by the refresh button).
    func runEffectsNow() {
        for effect in effects { effect(self) }
    }
}
