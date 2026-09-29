//
//  ScheduleView.swift
//  WatDash
//

import SwiftUI

/// Office hours are an optional layer, off until switched on. One preference
/// covers everywhere they could appear: Schedule, Today, the menu bar, the
/// widgets, course pages and Siri.
enum OfficeHoursLayer {
    static let key = "layers.officeHours"

    /// The saved switch, for code that isn't a view.
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func shows(_ kind: EventKind) -> Bool { isOn || kind != .officeHours }
}

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("schedule.mode") private var mode = "week"
    @AppStorage("schedule.weekends") private var showWeekends = false
    @AppStorage(OfficeHoursLayer.key) private var showOfficeHours = false
    @State private var courseFilter: String?

    var body: some View {
        @Bindable var router = router
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: router.scheduleFocus)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title(weekStart)).font(.title2.weight(.semibold))
                Spacer()
                Picker("Course", selection: $courseFilter) {
                    Text("All courses").tag(String?.none)
                    ForEach(store.courses) { Text($0.code).tag(Optional($0.code)) }
                }
                .fixedSize()
                HStack(spacing: 14) {
                    Toggle("Office hours", isOn: $showOfficeHours)
                        .help("Show office hours here, on Today, in the menu bar and in widgets")
                        .onChange(of: showOfficeHours) { _, _ in SnapshotWriter.write(from: store) }
                    Toggle("Weekends", isOn: $showWeekends)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Picker("", selection: $mode) {
                    Text("Week").tag("week")
                    Text("Agenda").tag("agenda")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                ControlGroup {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button("Today") { router.scheduleFocus = .now }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            if mode == "week" {
                WeekGrid(weekStart: weekStart, days: showWeekends ? 7 : 5, courseFilter: courseFilter, showOfficeHours: showOfficeHours)
            } else {
                AgendaList(start: weekStart, courseFilter: courseFilter, showOfficeHours: showOfficeHours)
            }
        }
        .navigationTitle("Schedule")
    }

    private func shift(_ weeks: Int) {
        router.scheduleFocus = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: router.scheduleFocus) ?? router.scheduleFocus
    }

    private func title(_ weekStart: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: showWeekends ? 6 : 4, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

// MARK: - Week grid

struct WeekGrid: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var weekStart: Date
    var days: Int
    var courseFilter: String?
    var showOfficeHours: Bool

    private let hourHeight: CGFloat = 54
    private let gutter: CGFloat = 52

    var body: some View {
        let calendar = Calendar.current
        let dayDates = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let window = DateInterval(start: weekStart, end: calendar.date(byAdding: .day, value: days, to: weekStart) ?? weekStart)
        let items = store.agenda(in: window).filter {
            (courseFilter == nil || $0.courseCode == courseFilter) && (showOfficeHours || $0.kind != .officeHours)
        }
        let allDay = items.filter(\.isAllDay)
        let hours = TimeGrid.hours(for: items, calendar: calendar)
        let startHour = hours.lowerBound
        let endHour = hours.upperBound

        VStack(spacing: 0) {
            // Day headers + all-day strip.
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(dayDates, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(day.formatted(.dateTime.day()))
                                .font(.callout.weight(.bold))
                                .foregroundStyle(isToday ? .white : .primary)
                                .frame(minWidth: 24, minHeight: 24)
                                .background(isToday ? Palette.bad : .clear, in: Circle())
                        }
                        let dayAllDay = allDay.filter { $0.start <= day && calendar.date(byAdding: .day, value: 1, to: day)! <= $0.end || calendar.isDate($0.start, inSameDayAs: day) }
                        ForEach(dayAllDay) { item in
                            Text(item.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((item.kind == .holiday ? Palette.good : store.color(for: item.courseCode)).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
            .padding(.trailing, 12)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        // Hour labels.
                        VStack(spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                Text(hourLabel(hour))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: gutter - 6, height: hourHeight, alignment: .topTrailing)
                                    .offset(y: -6)
                                    .id(hour)
                            }
                        }
                        ForEach(dayDates, id: \.self) { day in
                            DayColumn(
                                day: day,
                                items: items.filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: day) },
                                startHour: startHour, endHour: endHour, hourHeight: hourHeight
                            )
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }
                .onAppear { proxy.scrollTo(max(startHour, min(endHour - 8, calendar.component(.hour, from: store.now) - 1)), anchor: .top) }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(hour < 12 ? "AM" : "PM")"
    }
}

struct DayColumn: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var day: Date
    var items: [AgendaItem]
    var startHour: Int
    var endHour: Int
    var hourHeight: CGFloat
    @State private var selected: AgendaItem?

    var body: some View {
        let calendar = Calendar.current
        let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        let layout = Self.columns(for: items)
        let gridHeight = CGFloat(endHour - startHour) * hourHeight
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                // Hour lines.
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Divider()
                            Spacer()
                        }
                        .frame(height: hourHeight)
                    }
                }
                Rectangle().fill(.separator.opacity(0.5)).frame(width: 0.5).frame(maxHeight: .infinity)

                ForEach(items) { item in
                    let slot = layout[item.id] ?? (0, 1)
                    let top = max(0, CGFloat(item.start.timeIntervalSince(dayStart) / 3600) * hourHeight)
                    let rawHeight = CGFloat(item.end.timeIntervalSince(item.start) / 3600) * hourHeight
                    let height = item.isDue ? 22 : max(20, min(rawHeight, gridHeight - top))
                    let columnWidth = (width - 6) / CGFloat(slot.1)
                    EventBlock(item: item, compact: height < 40)
                        .frame(width: columnWidth - 2, height: height)
                        // Past the last hour (an 11:59 PM deadline), sit flush with the bottom.
                        .offset(x: 3 + CGFloat(slot.0) * columnWidth, y: min(top, gridHeight - height))
                        .onTapGesture { selected = item }
                        .popover(isPresented: Binding(get: { selected?.id == item.id }, set: { if !$0 { selected = nil } }), arrowEdge: .trailing) {
                            EventPopover(item: item) { selected = nil }
                        }
                }

                if calendar.isDateInToday(day) {
                    let y = CGFloat(store.now.timeIntervalSince(dayStart) / 3600) * hourHeight
                    if y >= 0 && y <= gridHeight {
                        HStack(spacing: 0) {
                            Circle().fill(Palette.bad).frame(width: 8, height: 8)
                            Rectangle().fill(Palette.bad).frame(height: 1.5)
                        }
                        .offset(x: -4, y: y - 4)
                        .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                let minutes = Int(location.y / hourHeight * 60 / 15) * 15
                let start = calendar.date(byAdding: .minute, value: minutes, to: dayStart)
                router.sheet = .newEvent(start)
            }
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
    }

    /// Side-by-side columns for overlapping items: (column, columns in cluster).
    static func columns(for items: [AgendaItem]) -> [String: (Int, Int)] {
        let sorted = items.sorted { $0.start < $1.start }
        var result: [String: (Int, Int)] = [:]
        var cluster: [AgendaItem] = []
        var clusterEnd = Date.distantPast
        var columnEnds: [Date] = []

        func flush() {
            let count = max(1, columnEnds.count)
            for item in cluster { result[item.id] = (result[item.id]?.0 ?? 0, count) }
            cluster = []
            columnEnds = []
        }

        for item in sorted {
            let end = item.isDue ? item.start.addingTimeInterval(TimeGrid.dueFootprint) : item.end
            if item.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = end
                result[item.id] = (free, 1)
            } else {
                columnEnds.append(end)
                result[item.id] = (columnEnds.count - 1, 1)
            }
            cluster.append(item)
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return result
    }
}

struct EventBlock: View {
    @Environment(AppStore.self) private var store
    var item: AgendaItem
    var compact: Bool

    var body: some View {
        let color = item.kind == .event || item.courseCode == nil ? Palette.accentDeep : store.color(for: item.courseCode)
        let strong = item.kind.isAssessment
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.isDue || strong { Image(systemName: item.kind.symbol).font(.system(size: 9, weight: .bold)) }
                Text(item.title).font(.caption.weight(.semibold)).lineLimit(compact ? 1 : 2)
            }
            if !compact {
                Text([item.start.shortTime, item.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(strong ? .white : color)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(strong ? color.opacity(0.92) : color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            if !strong { Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5)) }
        }
        .opacity(item.isDone ? 0.5 : 1)
        .clipped()
        .contentShape(Rectangle())
    }
}

struct EventPopover: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var item: AgendaItem
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KindIcon(kind: item.kind, color: store.color(for: item.courseCode))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.headline)
                    Text(item.kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(item.isAllDay ? item.start.formatted(date: .complete, time: .omitted)
                      : "\(item.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), \(item.start.shortTime)\(item.isDue ? "" : " – \(item.end.shortTime)")",
                      systemImage: "clock")
                if let location = item.location { Label(location, systemImage: "mappin.and.ellipse") }
                if let detail = item.detail { Label(detail, systemImage: "text.alignleft").lineLimit(4) }
                if item.kind.isSeated { SeatingButton() }
                if case let .event(id) = item.origin, let event = store.event(id: id) {
                    if let recurrence = event.recurrence { Label(recurrence.summary, systemImage: "repeat") }
                    if let source = store.source(id: event.sourceID) {
                        Label("From \(source.name)", systemImage: source.kind.symbol).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            Divider()
            HStack {
                switch item.origin {
                case let .event(id):
                    Button("Edit…") { close(); router.sheet = .editEvent(id) }
                    if store.event(id: id)?.recurrence != nil {
                        Button("Skip This One") { store.skipOccurrence(eventID: id, at: item.start); close() }
                    } else {
                        Button("Delete", role: .destructive) { store.deleteEvent(id: id); close() }
                    }
                case let .assessment(id):
                    Button("Edit…") { close(); router.sheet = .editAssessment(id) }
                    Button(item.isDone ? "Mark Not Done" : "Mark Done") { store.toggleDone(item); close() }
                }
                Spacer()
                if let code = item.courseCode, let course = store.course(code: code) {
                    Button(code) { close(); router.selection = .course(course.id) }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Agenda

struct AgendaList: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var start: Date
    var courseFilter: String?
    var showOfficeHours: Bool

    var body: some View {
        let calendar = Calendar.current
        let window = DateInterval(start: calendar.startOfDay(for: min(start, store.now)), duration: 28 * 86_400)
        let items = store.agenda(in: window).filter {
            (courseFilter == nil || $0.courseCode == courseFilter) && (showOfficeHours || $0.kind != .officeHours)
        }
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.start) }
        List {
            ForEach(grouped.keys.sorted(), id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    ForEach(grouped[day] ?? []) { item in
                        AgendaRow(item: item)
                            .onTapGesture(count: 2) {
                                switch item.origin {
                                case let .event(id): router.sheet = .editEvent(id)
                                case let .assessment(id): router.sheet = .editAssessment(id)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
