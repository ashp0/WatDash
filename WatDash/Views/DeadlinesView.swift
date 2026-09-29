//
//  DeadlinesView.swift
//  WatDash
//

import SwiftUI

/// Every marked thing, grouped by when it lands: this week, next week,
/// later, not yet dated, and done.
struct DeadlinesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var courseFilter: String?
    @State private var showDone = false

    var body: some View {
        let calendar = Calendar.current
        let now = store.now
        let thisWeekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfWeek(for: now))!
        let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: thisWeekEnd)!
        let horizon = DateInterval(start: calendar.date(byAdding: .day, value: -60, to: now)!, end: max(store.settings.termEnd, now).addingTimeInterval(30 * 86_400))
        let items = store.agenda(in: horizon).filter { ($0.kind.isAssessment || $0.kind.isDue) && (courseFilter == nil || $0.courseCode == courseFilter) }
        let open = items.filter { !$0.isDone && $0.end >= now }
        let groups: [(String, [AgendaItem])] = [
            ("Overdue", items.filter { !$0.isDone && $0.end < now && $0.isDue }),
            ("This week", open.filter { $0.start < thisWeekEnd }),
            ("Next week", open.filter { $0.start >= thisWeekEnd && $0.start < nextWeekEnd }),
            ("Later this term", open.filter { $0.start >= nextWeekEnd }),
        ]
        let undated = store.undatedAssessments.filter { courseFilter == nil || $0.courseCode == courseFilter }
        let done = items.filter(\.isDone).reversed()

        List {
            ForEach(groups, id: \.0) { title, rows in
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { row($0) }
                    } header: {
                        Text("\(title) · \(rows.count)")
                    }
                }
            }
            if !undated.isEmpty {
                Section("Date to be announced · \(undated.count)") {
                    ForEach(undated) { assessment in
                        HStack {
                            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                            CourseChip(code: assessment.courseCode, compact: true)
                            Text(assessment.title)
                            Spacer()
                            Text("TBA").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { router.sheet = .editAssessment(assessment.id) }
                    }
                }
            }
            if showDone && !done.isEmpty {
                Section("Done") {
                    ForEach(Array(done)) { row($0) }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if groups.allSatisfy(\.1.isEmpty) && undated.isEmpty {
                EmptyState(symbol: "flag.checkered", title: "Nothing due", message: "Import course folders or a LEARN feed to fill this in.",
                           actionTitle: "Import") { router.selection = .importCenter }
            }
        }
        .navigationTitle("Deadlines")
        .toolbar {
            ToolbarItemGroup {
                Picker("Course", selection: $courseFilter) {
                    Text("All courses").tag(String?.none)
                    ForEach(store.courses) { Text($0.code).tag(Optional($0.code)) }
                }
                Toggle("Show done", isOn: $showDone)
                Button { router.sheet = .newAssessment(courseFilter) } label: { Label("New Assessment", systemImage: "plus") }
            }
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggleDone(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? Palette.good : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            AgendaRow(item: item, showDate: true, showCountdown: true)
            if case let .assessment(id) = item.origin, let assessment = store.assessment(id: id) {
                if let percent = assessment.percent {
                    Text("\(percent.oneDecimal)%")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.margin(percent - store.settings.targetAverage))
                }
                if item.kind.isSeated {
                    SeatingButton(compact: true)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button {
                        router.sheet = .studyPrompt(assessment.courseCode, assessment.id)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.borderless)
                    .help("Make a Claude Code prompt for a study page")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            switch item.origin {
            case let .event(id): router.sheet = .editEvent(id)
            case let .assessment(id): router.sheet = .editAssessment(id)
            }
        }
        .contextMenu {
            if case let .assessment(id) = item.origin {
                Button("Edit…") { router.sheet = .editAssessment(id) }
                Button("Delete", role: .destructive) { store.deleteAssessment(id: id) }
            }
        }
    }
}
