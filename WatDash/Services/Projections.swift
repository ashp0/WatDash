//
//  Projections.swift
//  WatDash
//

import Foundation
import UserNotifications
import WidgetKit

/// Writes the widget snapshot and asks WidgetKit to reload. Runs after every
/// commit (debounced) and every 15 minutes, so the "Up next" data never lags
/// the store by more than a few seconds. The widgets are Mac-only (see
/// Tools/generate_project.py), so on iOS there's nothing to write.
enum SnapshotWriter {
    @MainActor
    static func write(from store: AppStore) {
        #if os(macOS)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: store.now)
        let window = DateInterval(start: start, duration: 10 * 86_400)
        let items = store.agenda(in: window).filter { !$0.isDone && OfficeHoursLayer.shows($0.kind) }.prefix(120).map { item in
            WidgetSnapshot.Item(
                id: item.id, title: item.title, courseCode: item.courseCode,
                colorIndex: store.colorIndex(for: item.courseCode),
                kindLabel: item.kind.label, symbol: item.kind.symbol,
                start: item.start, end: item.end, location: item.location,
                isDue: item.isDue, isClass: item.kind.isClassMeeting, isAssessment: item.kind.isAssessment,
                detail: item.detail
            )
        }

        let term = store.term
        var average: WidgetSnapshot.Average?
        if term.units > 0 {
            average = WidgetSnapshot.Average(
                projected: term.projected, low: term.low, high: term.high, floor: term.floor,
                target: term.target, probability: term.probabilityAtLeastTarget,
                required: requirementText(term.requiredOnRemaining),
                courses: term.courses.map { result in
                    WidgetSnapshot.CourseLine(code: result.code, colorIndex: store.colorIndex(for: result.code) ?? 0,
                                              current: result.current, projected: result.projected)
                }
            )
        }

        let snapshot = WidgetSnapshot(generatedAt: .now, termName: store.settings.termName, items: Array(items), average: average)
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Log.store.error("Widget snapshot not written: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    static func requirementText(_ requirement: GradeEngine.Requirement) -> String {
        switch requirement {
        case .secured: "Target secured"
        case .unreachable: "Out of reach this term"
        case let .needs(value): "Need \(Int(value.rounded(.up)))% on what's left"
        case .noRemainingWork: "All marks in"
        case .noScheme: "Add grading schemes"
        }
    }
}

/// Deadline (and optional class) reminders, reconciled like WatAlarm's alarms:
/// identifiers are derived from what the reminder is for, so a resync is a set
/// difference and never a duplicate.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "watdash."
    private(set) var authorized: Bool?

    func requestAuthorization() async {
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
    }

    func reconcile(store: AppStore) {
        let settings = store.settings
        guard settings.notifyDeadlines || settings.notifyClasses else {
            removeAll()
            return
        }
        let now = Date.now
        let window = DateInterval(start: now, duration: 21 * 86_400)
        var desired: [String: UNNotificationRequest] = [:]

        for item in store.agenda(in: window) where !item.isDone {
            let course = item.courseCode.map { "\($0) · " } ?? ""
            if settings.notifyDeadlines, item.kind.isAssessment || item.kind.isDue {
                for hours in settings.deadlineLeadHours {
                    let fire = item.start.addingTimeInterval(-hours * 3600)
                    guard fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "\(course)\(item.title)"
                    let when = hours >= 24 ? "tomorrow" : "in \(Int(hours)) hour\(hours == 1 ? "" : "s")"
                    content.body = item.isDue
                        ? "Due \(when) at \(item.start.shortTime)."
                        : "\(item.kind.label) \(when) at \(item.start.shortTime)\(item.location.map { " in \($0)" } ?? "")."
                    content.sound = .default
                    content.userInfo = ["itemID": item.id]
                    add(content, fire: fire, key: "d|\(item.id)|\(hours)|\(item.start.timeIntervalSince1970)", into: &desired)
                }
            }
            if settings.notifyClasses, item.kind.isClassMeeting {
                let fire = item.start.addingTimeInterval(-settings.classLeadMinutes * 60)
                guard fire > now, fire < now.addingTimeInterval(3 * 86_400) else { continue }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = "Starts at \(item.start.shortTime)\(item.location.map { " in \($0)" } ?? "")."
                content.sound = .default
                add(content, fire: fire, key: "c|\(item.id)|\(item.start.timeIntervalSince1970)", into: &desired)
            }
        }

        // macOS, like iOS, only keeps a limited number pending: keep the soonest.
        let kept = desired.values
            .sorted { fireDate($0) < fireDate($1) }
            .prefix(60)
        let keptIDs = Set(kept.map(\.identifier))

        center.getPendingNotificationRequests { [center, prefix] pending in
            let ours = pending.filter { $0.identifier.hasPrefix(prefix) }
            let stale = ours.map(\.identifier).filter { !keptIDs.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let existing = Set(ours.map(\.identifier))
            for request in kept where !existing.contains(request.identifier) {
                center.add(request)
            }
        }
    }

    private func add(_ content: UNMutableNotificationContent, fire: Date, key: String, into desired: inout [String: UNNotificationRequest]) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = prefix + DeterministicID.digest(key)
        desired[id] = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }

    func removeAll() {
        center.getPendingNotificationRequests { [center, prefix] pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    /// One-off notification, e.g. "a seat opened in RUSS 101".
    func notifyNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: prefix + "now." + UUID().uuidString, content: content, trigger: nil))
    }
}
