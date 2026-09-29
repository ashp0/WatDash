//
//  CalendarSync.swift
//  WatDash
//

import AppKit
import EventKit
import Foundation

/// Two directions through EventKit:
///
/// * **Import** — read calendars you already have (Google, Outlook, iCloud:
///   anything added in System Settings → Internet Accounts) into the store.
/// * **Export** — keep dedicated "WatDash · Classes" and "WatDash · Deadlines"
///   calendars in step with the store, so your phone and watch see the same
///   term. WatDash owns those calendars outright, which is what makes the
///   export safe to rebuild: it reconciles against its own keys and never
///   touches an event it didn't create.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var lastExport: Date?
    private(set) var lastExportSummary: String?
    private var exportTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            status = EKEventStore.authorizationStatus(for: .event)
            Log.calendar.error("Calendar access failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Re-import Apple Calendar sources when the user's calendars change.
    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in handler() }
        }
    }

    // MARK: - Import

    struct CalendarChoice: Identifiable, Hashable {
        var id: String
        var title: String
        var sourceTitle: String
        var colorComponents: [Double]
    }

    func availableCalendars() -> [CalendarChoice] {
        let ours = Set(CalendarSync.ownTitles)
        return store.calendars(for: .event)
            .filter { !ours.contains($0.title) }
            .map { calendar in
                let color = calendar.color?.usingColorSpace(.sRGB)
                return CalendarChoice(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    colorComponents: [Double(color?.redComponent ?? 0.5), Double(color?.greenComponent ?? 0.5), Double(color?.blueComponent ?? 0.5)]
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    /// Occurrences are imported already expanded — EventKit has applied every
    /// exception and detached edit, so there is nothing to re-derive.
    func importEvents(source: DataSource, into appStore: AppStore) {
        guard hasAccess else {
            appStore.recordSourceError(source.id, "Calendar access isn't granted.")
            return
        }
        let calendars = store.calendars(for: .event).filter { source.calendarIdentifiers.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            appStore.recordSourceError(source.id, "The chosen calendars no longer exist.")
            return
        }
        let start = min(appStore.settings.termStart, Date.now.addingTimeInterval(-30 * 86_400))
        let end = max(appStore.settings.termEnd, Date.now.addingTimeInterval(120 * 86_400))
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let known = appStore.knownCourseCodes
        let events: [DashEvent] = store.events(matching: predicate).compactMap { ekEvent in
            guard ekEvent.status != .canceled else { return nil }
            let title = ekEvent.title ?? "Untitled"
            let course = CourseCode.find(in: title, among: known)
            let kind = ICSImport.classify(summary: title, notes: ekEvent.notes, isAllDay: ekEvent.isAllDay, hasCourse: course != nil)
            let occurrence = ekEvent.occurrenceDate ?? ekEvent.startDate ?? .now
            return DashEvent(
                id: "\(source.id.uuidString):\(ekEvent.calendarItemIdentifier):\(Int(occurrence.timeIntervalSince1970))",
                title: title, courseCode: course, kind: kind,
                start: ekEvent.startDate, end: ekEvent.endDate, isAllDay: ekEvent.isAllDay,
                location: ekEvent.location?.nilIfEmpty, notes: ekEvent.notes?.nilIfEmpty,
                url: ekEvent.url?.absoluteString, timeZoneID: ekEvent.timeZone?.identifier,
                sourceID: source.id,
                cancelsClasses: kind == .holiday
            )
        }
        appStore.applyImport(sourceID: source.id, events: events)
    }

    // MARK: - Export

    static let classesTitle = "WatDash · Classes"
    static let deadlinesTitle = "WatDash · Deadlines"
    static var ownTitles: [String] { [classesTitle, deadlinesTitle] }
    private static let keyScheme = "watdash://occurrence/"

    func scheduleExport(_ appStore: AppStore) {
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.export(appStore)
        }
    }

    func export(_ appStore: AppStore) {
        let settings = appStore.settings
        guard settings.exportToAppleCalendar, hasAccess else { return }
        do {
            var created = 0, updated = 0, removed = 0
            let classCalendar = try ownCalendar(titled: CalendarSync.classesTitle, key: "classes", appStore: appStore, colorIndex: 0)
            let deadlineCalendar = try ownCalendar(titled: CalendarSync.deadlinesTitle, key: "deadlines", appStore: appStore, colorIndex: 3)

            let start = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-7 * 86_400))
            let end = max(appStore.settings.termEnd, Date.now.addingTimeInterval(60 * 86_400)).addingTimeInterval(86_400)
            let items = appStore.agenda(in: DateInterval(start: start, end: end))

            // Desired set, keyed deterministically.
            var desired: [String: (AgendaItem, EKCalendar)] = [:]
            for item in items where item.kind != .holiday {
                let isClass = item.kind.isClassMeeting || item.kind == .officeHours || item.kind == .event || item.kind == .other
                if isClass && !settings.exportClasses { continue }
                if !isClass && !settings.exportDeadlines { continue }
                let key = DeterministicID.digest("\(item.id)|\(item.title)|\(item.start.timeIntervalSince1970)|\(item.end.timeIntervalSince1970)|\(item.location ?? "")")
                desired[key] = (item, isClass ? classCalendar : deadlineCalendar)
            }

            // Existing events in our calendars.
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [classCalendar, deadlineCalendar])
            var existingKeys = Set<String>()
            for event in store.events(matching: predicate) {
                guard let url = event.url?.absoluteString, url.hasPrefix(CalendarSync.keyScheme) else {
                    // Not ours by key: a user-created event in our calendar. Leave it.
                    continue
                }
                let key = String(url.dropFirst(CalendarSync.keyScheme.count))
                if desired[key] == nil || existingKeys.contains(key) {
                    try store.remove(event, span: .thisEvent, commit: false)
                    removed += 1
                } else {
                    existingKeys.insert(key)
                }
            }

            for (key, (item, calendar)) in desired where !existingKeys.contains(key) {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                let course = item.courseCode.map { "\($0) " } ?? ""
                event.title = item.title.hasPrefix(course.trimmed) || course.isEmpty ? item.title : "\(course)\(item.title)"
                event.startDate = item.start
                event.endDate = item.end > item.start ? item.end : item.start.addingTimeInterval(item.isDue ? 15 * 60 : 3600)
                event.isAllDay = item.isAllDay
                event.location = item.location
                event.notes = [item.detail, "Managed by WatDash — edits here are overwritten."].compactMap { $0 }.joined(separator: "\n\n")
                event.url = URL(string: CalendarSync.keyScheme + key)
                if item.isDue { event.addAlarm(EKAlarm(relativeOffset: -24 * 3600)) }
                try store.save(event, span: .thisEvent, commit: false)
                created += 1
            }
            updated = existingKeys.count
            try store.commit()
            lastExport = .now
            lastExportSummary = "\(created) added, \(removed) removed, \(updated) unchanged"
            Log.calendar.info("Export: \(self.lastExportSummary ?? "", privacy: .public)")
        } catch {
            lastExportSummary = "Export failed: \(error.localizedDescription)"
            Log.calendar.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Finds (or creates) one of WatDash's calendars, preferring iCloud so the
    /// events reach your phone.
    private func ownCalendar(titled title: String, key: String, appStore: AppStore, colorIndex: Int) throws -> EKCalendar {
        if let id = appStore.settings.exportedCalendarIDs[key], let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let existing = store.calendars(for: .event).first(where: { $0.title == title }) {
            var settings = appStore.settings
            settings.exportedCalendarIDs[key] = existing.calendarIdentifier
            appStore.settings = settings
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        let rgb = Palette.courses[colorIndex]
        calendar.color = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        var settings = appStore.settings
        settings.exportedCalendarIDs[key] = calendar.calendarIdentifier
        appStore.settings = settings
        return calendar
    }

    /// Deletes WatDash's own calendars (Settings → Calendar → Remove).
    func removeOwnCalendars(_ appStore: AppStore) {
        for calendar in store.calendars(for: .event) where CalendarSync.ownTitles.contains(calendar.title) {
            try? store.removeCalendar(calendar, commit: true)
        }
        var settings = appStore.settings
        settings.exportedCalendarIDs = [:]
        settings.exportToAppleCalendar = false
        appStore.settings = settings
    }
}
