//
//  WatDashWidgets.swift
//  WatDashWidgets
//

import SwiftUI
import WidgetKit

#if !WIDGET_HARNESS
@main
#endif
struct WatDashWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        DeadlinesWidget()
        OverloadWidget()
        TodayWidget()
    }
}

// MARK: - Timeline

struct DashEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

/// Entries at "now" and at every item boundary in the next day, so "Up next"
/// flips on its own at the start and end of each class without the app running.
struct DashProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashEntry {
        DashEntry(date: .now, snapshot: SampleSnapshot.make(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(DashEntry(date: .now, snapshot: (context.isPreview && (snapshot?.items.isEmpty ?? true)) ? SampleSnapshot.make() : (snapshot ?? .empty), isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .empty
        let now = Date.now
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = Set<Date>([now])
        // Quarter-hour ticks keep the "in 2h 15m" labels honest between
        // boundaries; under an hour the label is a live timer instead.
        for step in 1...24 { dates.insert(now.addingTimeInterval(Double(step) * 15 * 60)) }
        for item in snapshot.items where item.start < horizon || item.end < horizon {
            if item.start > now && item.start < horizon { dates.insert(item.start) }
            if item.end > now && item.end < horizon { dates.insert(item.end) }
        }
        let entries = dates.sorted().prefix(40).map { DashEntry(date: $0, snapshot: snapshot, isPlaceholder: false) }
        // Ask again in a few hours even if nothing changes; the app also
        // reloads timelines whenever its data changes.
        completion(Timeline(entries: Array(entries), policy: .after(now.addingTimeInterval(3 * 3600))))
    }
}

// MARK: - Shared bits

/// "in 2h 15m" beyond an hour, a ticking 24:59 inside it.
private struct Countdown: View {
    var target: Date
    var now: Date

    var body: some View {
        let seconds = target.timeIntervalSince(now)
        if seconds <= 0 {
            Text("now")
        } else if seconds < 3600 {
            Text(timerInterval: now...target, countsDown: true)
                .monospacedDigit()
        } else {
            let minutes = Int(seconds) / 60
            let hours = minutes / 60
            let days = hours / 24
            Text(days >= 1 ? (days < 3 && hours % 24 > 0 ? "\(days)d \(hours % 24)h" : "\(days)d")
                 : (minutes % 60 > 0 ? "\(hours)h \(minutes % 60)m" : "\(hours)h"))
                .monospacedDigit()
        }
    }
}

private func color(_ item: WidgetSnapshot.Item) -> Color {
    item.colorIndex.map(Palette.color) ?? Palette.accentDeep
}

private struct ItemLine: View {
    var item: WidgetSnapshot.Item
    var now: Date
    var showDay = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(color(item)).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if item.start > now {
                Countdown(target: item.start, now: now)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 56, alignment: .trailing)
            }
        }
        .frame(height: 26)
    }

    private var detail: String {
        let day = showDay ? (Calendar.current.isDateInToday(item.start) ? "Today " : item.start.formatted(.dateTime.weekday(.abbreviated)) + " ") : ""
        let time = item.start.formatted(date: .omitted, time: .shortened)
        return [day + (item.isDue ? "due \(time)" : time), item.location].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct Header: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Palette.accentDeep)
            Text(title)
        }
        .font(.caption.weight(.bold))
    }
}

private struct EmptyNote: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Up next

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: DashProvider()) { entry in
            UpNextView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watdash://schedule"))
        }
        .configurationDisplayName("Up Next")
        .description("The class you're in and what's coming next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpNextView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var entry: DashEntry
    /// Lets previews and the render harness pick a size explicitly.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let now = entry.date
        let current = entry.snapshot.current(at: now)
        let upcoming = entry.snapshot.items.filter { $0.start > now }
        VStack(alignment: .leading, spacing: 6) {
            Header(title: current != nil ? "Now" : "Up next", symbol: "clock")
            if let focus = current ?? upcoming.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.title)
                        .font(.headline)
                        .foregroundStyle(color(focus))
                        .lineLimit(2)
                    if let location = focus.location {
                        Text(location).font(.caption).foregroundStyle(.secondary)
                    }
                    if current != nil {
                        Text("ends \(focus.end.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                        ProgressView(timerInterval: focus.start...focus.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(color(focus))
                    } else {
                        HStack(spacing: 4) {
                            Text("in").foregroundStyle(.secondary)
                            Countdown(target: focus.start, now: now)
                        }
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.accentDeep)
                        Text(focus.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if family == .systemMedium {
                    let rest = upcoming.filter { $0.id != focus.id }.prefix(2)
                    ForEach(Array(rest)) { ItemLine(item: $0, now: now, showDay: true) }
                }
                Spacer(minLength: 0)
            } else {
                EmptyNote(text: "Nothing coming up.")
            }
        }
    }
}

// MARK: - Deadlines

struct DeadlinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Deadlines", provider: DashProvider()) { entry in
            DeadlinesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watdash://deadlines"))
        }
        .configurationDisplayName("Deadlines")
        .description("Assignments, quizzes and exams coming up.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DeadlinesView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var entry: DashEntry
    /// Lets previews and the render harness pick a size explicitly.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let items = entry.snapshot.deadlines(after: entry.date, limit: family == .systemLarge ? 10 : 4)
        VStack(alignment: .leading, spacing: 4) {
            Header(title: "Deadlines", symbol: "flag")
            if items.isEmpty {
                EmptyNote(text: "Nothing due soon.")
            } else {
                ForEach(items) { ItemLine(item: $0, now: entry.date, showDay: true) }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Overload tracker

struct OverloadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Overload", provider: DashProvider()) { entry in
            OverloadView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watdash://grades"))
        }
        .configurationDisplayName("Overload Tracker")
        .description("Projected average against the 80% line for a sixth course.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct OverloadView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var entry: DashEntry
    /// Lets previews and the render harness pick a size explicitly.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let average = entry.snapshot.average, let projected = average.projected {
            let margin = projected - average.target
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Header(title: "Average", symbol: "gauge.with.dots.needle.67percent")
                    Gauge(value: min(100, max(0, projected)), in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(projected.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Palette.margin(margin))
                    .scaleEffect(1.25)
                    .frame(height: 64)
                    Text("\(margin >= 0 ? "+" : "−")\(abs(margin).formatted(.number.precision(.fractionLength(1)))) vs \(Int(average.target))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.margin(margin))
                    Text(average.required).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                if family == .systemMedium {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(average.courses.prefix(6)) { course in
                            HStack(spacing: 6) {
                                Circle().fill(Palette.color(course.colorIndex)).frame(width: 6, height: 6)
                                Text(course.code).font(.caption2.weight(.semibold)).frame(width: 64, alignment: .leading)
                                Text(course.current.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                                    .font(.caption2.monospacedDigit())
                                Spacer(minLength: 0)
                            }
                        }
                        if let p = average.probability {
                            Text("\(Int((p * 100).rounded()))% chance ≥ \(Int(average.target))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading) {
                Header(title: "Average", symbol: "gauge.with.dots.needle.67percent")
                EmptyNote(text: "Add grading schemes and marks in WatDash.")
            }
        }
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: DashProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watdash://schedule"))
        }
        .configurationDisplayName("Today")
        .description("Today's classes, quizzes and deadlines.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

struct TodayView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var entry: DashEntry
    /// Lets previews and the render harness pick a size explicitly.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let today = entry.snapshot.items(on: entry.date).filter { $0.end >= entry.date || $0.isDue }
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
        let list = today.isEmpty ? entry.snapshot.items(on: tomorrowDate) : today
        VStack(alignment: .leading, spacing: 4) {
            Header(title: today.isEmpty ? "Tomorrow" : entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), symbol: "calendar")
            if list.isEmpty {
                EmptyNote(text: "A clear day.")
            } else {
                ForEach(list.prefix(family == .systemLarge ? 10 : 4)) { ItemLine(item: $0, now: entry.date) }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Placeholder data

enum SampleSnapshot {
    static func make() -> WidgetSnapshot {
        let now = Date.now
        func item(_ title: String, _ code: String, _ color: Int, _ minutes: Double, _ length: Double, _ location: String?, due: Bool = false, assessment: Bool = false) -> WidgetSnapshot.Item {
            let start = now.addingTimeInterval(minutes * 60)
            return .init(id: title, title: title, courseCode: code, colorIndex: color, kindLabel: "", symbol: "circle",
                         start: start, end: start.addingTimeInterval(length * 60), location: location,
                         isDue: due, isClass: !due && !assessment, isAssessment: assessment || due, detail: nil)
        }
        return WidgetSnapshot(
            generatedAt: now, termName: "Fall 2026",
            items: [
                item("MATH 137 LEC 004", "MATH 137", 0, 25, 50, "MC 2065"),
                item("MATH 135 LEC 003", "MATH 135", 1, 145, 50, "MC 2066"),
                item("Assignment W3", "MATH 135", 1, 300, 0, nil, due: true),
                item("Quiz 3", "MATH 137", 0, 1500, 50, "Odyssey seat", assessment: true),
            ],
            average: .init(projected: 82.4, low: 78.9, high: 85.9, floor: 21, target: 80, probability: 0.74,
                           required: "Need 76% on what's left", courses: [.init(code: "MATH 137", colorIndex: 0, current: 88, projected: 83)])
        )
    }
}
