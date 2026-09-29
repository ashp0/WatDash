//
//  RootView.swift
//  WatDash
//

import SwiftUI
import UniformTypeIdentifiers

/// The main window. On the Mac and a full-width iPad: a sidebar and the
/// selected screen. On iPhone (or an iPad window narrow enough to get the
/// iPhone layout): tabs for the four screens checked most, the rest under
/// More. Both read and write the same `Router.selection`.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var compact

    var body: some View {
        @Bindable var router = router
        Group {
            if compact {
                #if os(iOS)
                CompactRoot()
                #endif
            } else {
                split
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
        #if os(iOS)
        .modifier(FilePickerHost())
        #endif
    }

    private var split: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            DetailView(item: router.selection ?? .today)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                // iPad shows a column's own toolbar, not the split view's.
                .toolbar { RootToolbar(store: store, router: router) }
                #endif
        }
        #if os(macOS)
        .toolbar { RootToolbar(store: store, router: router) }
        #endif
    }
}

/// The screen for a sidebar item, shared by the split view and the tabs.
struct DetailView: View {
    @Environment(AppStore.self) private var store
    var item: SidebarItem

    var body: some View {
        switch item {
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

/// Capture, add and refresh, on every screen.
struct RootToolbar: ToolbarContent {
    var store: AppStore
    var router: Router

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { QuickCapture.show() } label: {
                Label("Quick Capture", systemImage: "bolt")
            }
            #if os(macOS)
            .help("Quick capture (⌘K, or ⌃⌥Space from any app)")
            #endif
            Menu {
                Button("New Event…", systemImage: "calendar.badge.plus") { router.sheet = .newEvent(nil) }
                Button("New Assessment…", systemImage: "checklist") { router.sheet = .newAssessment(nil) }
                Divider()
                Button("Import Calendar File…", systemImage: "doc.badge.clock") { ImportActions.pickICSFile() }
                Button("Paste Quest Schedule…", systemImage: "list.clipboard") { router.sheet = .questPaste }
                Button("Scan Course Folders…", systemImage: "folder") { router.sheet = .courseFolders }
                #if os(iOS)
                Divider()
                Button("Refresh Everything", systemImage: "arrow.clockwise", action: refresh)
                #endif
            } label: {
                Label("Add", systemImage: "plus")
            }
            #if os(macOS)
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh feeds, folders and calendars (⌘R)")
            #endif
        }
    }

    private func refresh() {
        Task { await ImportService.shared.refreshAll(); store.runEffectsNow(); router.show("Everything refreshed.") }
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
                        .badge(store.badge(for: item))
                        .tag(item)
                }
            }
            Section("Courses") {
                ForEach(store.courses) { course in
                    CourseRow(course: course)
                        .tag(SidebarItem.course(course.id))
                        .contextMenu {
                            Button("Edit Course…") { router.sheet = .courseEditor(course.id) }
                            #if os(macOS)
                            if let folder = course.folderURL {
                                Button("Show Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                            }
                            #endif
                        }
                }
                if store.courses.isEmpty {
                    Button("Add your courses…") { router.selection = .importCenter }
                        .linkButtonStyle()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
        #if os(iOS)
        .navigationTitle("WatDash")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        #endif
    }
}

/// A course in the sidebar (and under More on iPhone): colour, code, title
/// and current grade.
struct CourseRow: View {
    @Environment(AppStore.self) private var store
    var course: Course

    var body: some View {
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
    }
}

extension AppStore {
    /// Sidebar and tab badges: deadlines in the next three days, captures to confirm.
    func badge(for item: SidebarItem) -> Int {
        switch item {
        case .deadlines: upcomingDeadlines(days: 3).count
        case .importCenter: proposedEvents.count
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

#if os(iOS)
/// iPhone, and iPad windows narrow enough for the iPhone layout: Today,
/// Schedule, Deadlines and Grades as tabs; Study, Import, the courses and
/// Settings under More.
struct CompactRoot: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    enum CompactTab: Hashable {
        case today, schedule, deadlines, grades, more
    }

    var body: some View {
        TabView(selection: tab) {
            Tab(SidebarItem.today.title, systemImage: SidebarItem.today.symbol, value: .today) { screen(.today) }
            Tab(SidebarItem.schedule.title, systemImage: SidebarItem.schedule.symbol, value: .schedule) { screen(.schedule) }
            Tab(SidebarItem.deadlines.title, systemImage: SidebarItem.deadlines.symbol, value: .deadlines) { screen(.deadlines) }
                .badge(store.badge(for: .deadlines))
            Tab(SidebarItem.grades.title, systemImage: SidebarItem.grades.symbol, value: .grades) { screen(.grades) }
            Tab("More", systemImage: "ellipsis", value: .more) { MoreTab() }
                .badge(store.badge(for: .importCenter))
        }
    }

    private func screen(_ item: SidebarItem) -> some View {
        NavigationStack {
            DetailView(item: item)
                .toolbar { RootToolbar(store: store, router: router) }
        }
    }

    /// The four tabbed screens map to themselves; anything else (a course,
    /// Study, Import, or nothing) lives under More.
    private var tab: Binding<CompactTab> {
        Binding(
            get: {
                switch router.selection {
                case .today: .today
                case .schedule: .schedule
                case .deadlines: .deadlines
                case .grades: .grades
                default: .more
                }
            },
            set: { tab in
                switch tab {
                case .today: router.selection = .today
                case .schedule: router.selection = .schedule
                case .deadlines: router.selection = .deadlines
                case .grades: router.selection = .grades
                case .more: if !MoreTab.holds(router.selection) { router.selection = nil }
                }
            }
        )
    }
}

/// Study, Import, each course and Settings. The pushed screen is the router's
/// selection, so "Open grades" on a course card lands here, and going back
/// to the list clears it.
struct MoreTab: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    static func holds(_ item: SidebarItem?) -> Bool {
        switch item {
        case .study, .importCenter, .course: true
        default: false
        }
    }

    var body: some View {
        NavigationStack(path: path) {
            List {
                Section {
                    NavigationLink(value: SidebarItem.study) {
                        Label(SidebarItem.study.title, systemImage: SidebarItem.study.symbol)
                    }
                    NavigationLink(value: SidebarItem.importCenter) {
                        Label(SidebarItem.importCenter.title, systemImage: SidebarItem.importCenter.symbol)
                            .badge(store.badge(for: .importCenter))
                    }
                }
                Section("Courses") {
                    ForEach(store.courses) { course in
                        NavigationLink(value: SidebarItem.course(course.id)) { CourseRow(course: course) }
                    }
                    if store.courses.isEmpty {
                        Button("Add your courses…") { router.selection = .importCenter }
                    }
                }
                Section {
                    Button { router.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: SidebarItem.self) { item in
                DetailView(item: item)
                    .toolbar { RootToolbar(store: store, router: router) }
            }
        }
    }

    private var path: Binding<[SidebarItem]> {
        Binding(
            get: { Self.holds(router.selection) ? [router.selection].compactMap { $0 } : [] },
            set: { router.selection = $0.last }
        )
    }
}

/// Shows the file picker the router asks for. iOS has no open panel to run
/// from a menu, so pickers are presented from the window.
struct FilePickerHost: ViewModifier {
    @Environment(Router.self) private var router
    /// What was asked for; the router's value is cleared as the picker closes,
    /// before the result arrives.
    @State private var picking: Router.FilePicker?

    func body(content: Content) -> some View {
        let active = router.filePicker ?? picking
        content
            .fileImporter(
                isPresented: Binding(get: { router.filePicker != nil }, set: { if !$0 { router.filePicker = nil } }),
                allowedContentTypes: active == .outline ? [.html] : [UTType(filenameExtension: "ics") ?? .data],
                allowsMultipleSelection: active != .outline
            ) { result in
                guard case let .success(urls) = result else { return }
                switch picking {
                case .outline: if let url = urls.first { router.sheet = .outline(url) }
                default: ImportActions.importFiles(urls)
                }
            }
            .onChange(of: router.filePicker) { _, picker in
                if let picker { picking = picker }
            }
    }
}
#endif

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
        case let .newEvent(date): EventEditor(eventID: nil, initialDate: date)
        case let .editEvent(id): EventEditor(eventID: id, initialDate: nil)
        case let .newAssessment(code): AssessmentEditor(assessmentID: nil, courseCode: code)
        case let .editAssessment(id): AssessmentEditor(assessmentID: id, courseCode: nil)
        case let .studyPrompt(code, id): StudyPromptSheet(courseCode: code, assessmentID: id)
        case let .courseEditor(id): CourseEditor(courseID: id)
        case .inbox: InboxSheet()
        case .quickCapture:
            QuickCaptureView(close: { Router.shared.sheet = nil })
                .presentationDetents([.medium, .large])
        case .settings: SettingsView()
        }
    }
}
