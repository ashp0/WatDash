//
//  RootView.swift
//  WatDash
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { QuickCapturePanel.shared.show() } label: {
                    Label("Quick Capture", systemImage: "bolt")
                }
                .help("Quick capture (⌘K, or ⌃⌥Space from any app)")
                Menu {
                    Button("New Event…", systemImage: "calendar.badge.plus") { router.sheet = .newEvent(nil) }
                    Button("New Assessment…", systemImage: "checklist") { router.sheet = .newAssessment(nil) }
                    Divider()
                    Button("Import Calendar File…", systemImage: "doc.badge.clock") { ImportActions.pickICSFile() }
                    Button("Paste Quest Schedule…", systemImage: "list.clipboard") { router.sheet = .questPaste }
                    Button("Scan Course Folders…", systemImage: "folder") { router.sheet = .courseFolders }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    Task { await ImportService.shared.refreshAll(); store.runEffectsNow(); router.show("Everything refreshed.") }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh feeds, folders and calendars (⌘R)")
            }
        }
        .sheet(item: $router.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(store)
                .environment(router)
        }
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { router.toast = nil }
            }
        }
        .animation(.spring(duration: 0.35), value: router.toast)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            ImportActions.handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection ?? .today {
        case .today: DashboardView()
        case .schedule: ScheduleView()
        case .deadlines: DeadlinesView()
        case .grades: GradesView()
        case .study: StudyView()
        case .importCenter: ImportView()
        case let .course(id):
            if let course = store.courses.first(where: { $0.id == id }) {
                CourseDetailView(course: course)
            } else {
                EmptyState(symbol: "questionmark.folder", title: "Course removed", message: "Pick another course from the sidebar.")
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
            Section {
                ForEach([SidebarItem.today, .schedule, .deadlines, .grades, .study, .importCenter], id: \.self) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(badge(for: item))
                        .tag(item)
                }
            }
            Section("Courses") {
                ForEach(store.courses) { course in
                    HStack(spacing: 8) {
                        CourseDot(color: Palette.color(course.colorIndex), size: 9)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(course.code).font(.callout.weight(.medium))
                            if !course.title.isEmpty {
                                Text(course.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if let current = store.courseResult(course.code)?.current {
                            Text(current.noDecimals)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.course(course.id))
                    .contextMenu {
                        Button("Edit Course…") { router.sheet = .courseEditor(course.id) }
                        if let folder = course.folderURL {
                            Button("Show Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                    }
                }
                if store.courses.isEmpty {
                    Button("Add your courses…") { router.selection = .importCenter }
                        .buttonStyle(.link)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .deadlines: store.upcomingDeadlines(days: 3).count
        case .importCenter: store.proposedEvents.count
        default: 0
        }
    }
}

/// Term average at a glance, always visible at the bottom of the sidebar.
struct SidebarFooter: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let term = store.term
        Button {
            router.selection = .grades
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(Palette.margin(term.margin))
                VStack(alignment: .leading, spacing: 1) {
                    Text(term.projected.map { "Projected \($0.oneDecimal)" } ?? "No grades yet")
                        .font(.caption.weight(.semibold))
                    Text(term.margin.map { "\($0.signedOneDecimal) vs \(Int(term.target)) target" } ?? "Target \(Int(store.settings.targetAverage))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

/// Resolves a Router sheet to its view.
struct SheetHost: View {
    var sheet: Router.Sheet

    var body: some View {
        switch sheet {
        case .questPaste: QuestPasteSheet()
        case let .outline(url): OutlineImportSheet(url: url)
        case .courseFolders: CourseFolderSheet()
        case .feed: FeedSheet()
        case .appleCalendar: AppleCalendarSheet()
        case .openData: OpenDataSheet()
        case .dashboardGallery: WidgetGallerySheet()
        case let .newEvent(date): EventEditor(eventID: nil, initialDate: date)
        case let .editEvent(id): EventEditor(eventID: id, initialDate: nil)
        case let .newAssessment(code): AssessmentEditor(assessmentID: nil, courseCode: code)
        case let .editAssessment(id): AssessmentEditor(assessmentID: id, courseCode: nil)
        case let .studyPrompt(code, id): StudyPromptSheet(courseCode: code, assessmentID: id)
        case let .courseEditor(id): CourseEditor(courseID: id)
        case .inbox: InboxSheet()
        }
    }
}
