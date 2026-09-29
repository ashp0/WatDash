//
//  DashboardView.swift
//  WatDash
//

import SwiftUI
import UniformTypeIdentifiers

/// The Today screen: a grid of cards you choose, add, remove and drag into
/// order. The layout is part of settings, so it persists.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing = false
    @State private var dragging: DashboardWidget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if store.courses.isEmpty && store.events.isEmpty {
                    OnboardingCard()
                } else {
                    SetupChecklistCard()
                }
                DashboardGrid(spacing: 14) {
                    ForEach(store.settings.dashboard) { widget in
                        card(widget)
                            .overlay(alignment: .topTrailing) {
                                if editing {
                                    Button {
                                        withAnimation { remove(widget) }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .red)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                }
                            }
                            .rotationEffect(.degrees(editing ? (widget.hashValue % 2 == 0 ? 0.4 : -0.4) : 0))
                            .opacity(dragging == widget ? 0.4 : 1)
                            .layoutValue(key: SpanKey.self, value: widget.isWide ? 2 : 1)
                            .draggable(widget.rawValue) {
                                Label(widget.title, systemImage: widget.symbol)
                                    .padding(8)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                    .onAppear { dragging = widget }
                            }
                            .dropDestination(for: String.self) { items, _ in
                                dragging = nil
                                guard let raw = items.first, let moved = DashboardWidget(rawValue: raw) else { return false }
                                withAnimation(.snappy) { move(moved, before: widget) }
                                return true
                            }
                    }
                }
                if editing {
                    Button {
                        router.sheet = .dashboardGallery
                    } label: {
                        Label("Add Widget", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.tertiary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .animation(.snappy, value: store.settings.dashboard)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(editing ? "Done" : "Edit Widgets") {
                    withAnimation { editing.toggle() }
                    dragging = nil
                }
            }
        }
    }

    private var header: some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: store.now)
        let greeting = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let today = store.agenda(on: store.now)
        let classesLeft = today.filter { $0.kind.isClassMeeting && $0.end > store.now }.count
        let dueThisWeek = store.upcomingDeadlines(days: 7).count
        let week = max(1, calendar.dateComponents([.weekOfYear], from: calendar.startOfWeek(for: store.settings.termStart), to: store.now).weekOfYear.map { $0 + 1 } ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
            HStack(spacing: 8) {
                Text(store.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Text("·")
                Text("Week \(min(week, 16)) of \(store.settings.termName)")
                Text("·")
                Text("\(classesLeft) class\(classesLeft == 1 ? "" : "es") left today, \(dueThisWeek) due this week")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func card(_ widget: DashboardWidget) -> some View {
        switch widget {
        case .nowNext: NowNextCard()
        case .today: TodayCard()
        case .deadlines: DeadlinesCard()
        case .overload: OverloadCard()
        case .leverage: LeverageCard()
        case .weekLoad: WeekLoadCard()
        case .courseGrades: CourseGradesCard()
        case .importHub: ImportHubCard()
        case .study: StudyCard()
        case .countdown: CountdownCard()
        case .seatWatch: SeatWatchCard()
        case .inbox: InboxCard()
        }
    }

    private func remove(_ widget: DashboardWidget) {
        var settings = store.settings
        settings.dashboard.removeAll { $0 == widget }
        store.settings = settings
    }

    private func move(_ widget: DashboardWidget, before target: DashboardWidget) {
        guard widget != target else { return }
        var layout = store.settings.dashboard
        layout.removeAll { $0 == widget }
        let index = layout.firstIndex(of: target) ?? layout.endIndex
        layout.insert(widget, at: index)
        var settings = store.settings
        settings.dashboard = layout
        store.settings = settings
    }
}

// MARK: - Grid layout with column spans

struct SpanKey: LayoutValueKey {
    static let defaultValue = 1
}

/// Row-packing grid: 3 columns on a wide window, 2 otherwise; wide cards span
/// two. Cards in a row share the row's height so edges line up.
struct DashboardGrid: Layout {
    var spacing: CGFloat = 14

    private func columns(for width: CGFloat) -> Int { width > 1050 ? 3 : 2 }

    private struct Placement { var index: Int; var column: Int; var span: Int; var row: Int }

    private func pack(_ subviews: Subviews, columns: Int) -> [Placement] {
        var placements: [Placement] = []
        var row = 0
        var column = 0
        for (index, subview) in subviews.enumerated() {
            let span = min(columns, subview[SpanKey.self])
            if column + span > columns {
                row += 1
                column = 0
            }
            placements.append(Placement(index: index, column: column, span: span, row: row))
            column += span
        }
        return placements
    }

    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (placements: [Placement], rowHeights: [CGFloat], columnWidth: CGFloat) {
        let width = proposal.width ?? 900
        let count = columns(for: width)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let placements = pack(subviews, columns: count)
        var heights: [CGFloat] = Array(repeating: 0, count: (placements.map(\.row).max() ?? -1) + 1)
        for placement in placements {
            let itemWidth = columnWidth * CGFloat(placement.span) + spacing * CGFloat(placement.span - 1)
            let size = subviews[placement.index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            heights[placement.row] = max(heights[placement.row], size.height)
        }
        return (placements, heights, columnWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (_, heights, _) = metrics(proposal, subviews)
        let height = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: proposal.width ?? 900, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (placements, heights, columnWidth) = metrics(ProposedViewSize(width: bounds.width, height: nil), subviews)
        var rowY: [CGFloat] = []
        var y = bounds.minY
        for height in heights {
            rowY.append(y)
            y += height + spacing
        }
        for placement in placements {
            let x = bounds.minX + CGFloat(placement.column) * (columnWidth + spacing)
            let width = columnWidth * CGFloat(placement.span) + spacing * CGFloat(placement.span - 1)
            subviews[placement.index].place(
                at: CGPoint(x: x, y: rowY[placement.row]),
                proposal: ProposedViewSize(width: width, height: heights[placement.row])
            )
        }
    }
}

// MARK: - Gallery

struct WidgetGallerySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Widgets").font(.title2.weight(.semibold))
            Text("Cards for the Today screen. Drag them into order while editing.")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(DashboardWidget.allCases) { widget in
                        let added = store.settings.dashboard.contains(widget)
                        Button {
                            var settings = store.settings
                            if added { settings.dashboard.removeAll { $0 == widget } } else { settings.dashboard.append(widget) }
                            store.settings = settings
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: widget.symbol)
                                    .font(.title2)
                                    .foregroundStyle(Palette.accentDeep)
                                    .frame(width: 40, height: 40)
                                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(widget.title).font(.headline)
                                    Text(widget.subtitle).font(.caption).foregroundStyle(.secondary)
                                    Text(widget.isWide ? "Wide" : "Standard").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(added ? Palette.good : .secondary)
                                    .font(.title3)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Reset Layout") {
                    var settings = store.settings
                    settings.dashboard = DashboardWidget.defaultLayout
                    store.settings = settings
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640, height: 560)
    }
}
