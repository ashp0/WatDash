//
//  WatDashApp.swift
//  WatDash
//

import SwiftUI

@main
struct WatDashApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(OfficeHoursLayer.key) private var showOfficeHours = false
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var store = AppStore.shared
    @State private var router = Router.shared

    var body: some Scene {
        #if os(macOS)
        Window("WatDash", id: "main") {
            RootView()
                .environment(store)
                .environment(router)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
        .defaultLaunchBehavior(.presented)
        .commands { WatDashCommands(store: store, router: router) }

        Settings {
            SettingsView()
                .environment(store)
                .environment(router)
        }

        MenuBarExtra(isInserted: Binding(
            get: { store.settings.showMenuBarExtra },
            set: { store.settings.showMenuBarExtra = $0 }
        )) {
            MenuBarView()
                .environment(store)
                .environment(router)
        } label: {
            // Read here, in the scene body, so the scene itself depends on
            // the clock and the agenda and rebuilds the label when either
            // moves (see MenuBarLabel).
            MenuBarLabel(status: store.menuBarStatus(officeHours: showOfficeHours))
        }
        .menuBarExtraStyle(.window)
        #else
        // iPhone and iPad: one window scene (iPad can open several), with
        // settings as a sheet and no menu bar.
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .onOpenURL { AppLaunch.open($0) }
        }
        .commands { WatDashCommands(store: store, router: router) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.saveNow() }
        }
        #endif
    }
}

/// App-wide navigation state, shared with the menu bar extra, the hotkey
/// panel and App Intents so any of them can open the right screen.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var selection: SidebarItem? = .today
    var sheet: Sheet?
    var scheduleFocus: Date = .now
    var toast: String?
    /// SwiftUI's openWindow action, captured from a view that always exists
    /// (the menu bar label), so AppKit code can reopen the main window.
    @ObservationIgnored var openWindowAction: OpenWindowAction?

    /// A file picker to show (iOS; the Mac uses open panels, see ImportActions).
    var filePicker: FilePicker?

    enum FilePicker: Equatable {
        case calendarFiles, outline
    }

    enum Sheet: Identifiable, Equatable {
        case questPaste, outline(URL), courseFolders, feed, appleCalendar, openData
        case newEvent(Date?), editEvent(String), newAssessment(String?), editAssessment(UUID), studyPrompt(String, UUID?)
        case courseEditor(UUID), inbox
        /// iPhone and iPad only: the Mac has a capture panel and a Settings window.
        case quickCapture, settings

        var id: String {
            switch self {
            case .questPaste: "quest"
            case let .outline(url): "outline-\(url.path)"
            case .courseFolders: "folders"
            case .feed: "feed"
            case .appleCalendar: "apple"
            case .openData: "opendata"
            case let .newEvent(date): "new-event-\(date?.timeIntervalSince1970 ?? 0)"
            case let .editEvent(id): "event-\(id)"
            case let .newAssessment(code): "new-assessment-\(code ?? "")"
            case let .editAssessment(id): "assessment-\(id)"
            case let .studyPrompt(code, id): "study-\(code)-\(id?.uuidString ?? "")"
            case let .courseEditor(id): "course-\(id)"
            case .inbox: "inbox"
            case .quickCapture: "capture"
            case .settings: "settings"
            }
        }
    }

    /// Opens the editor for whatever an agenda row stands for.
    func open(_ item: AgendaItem) {
        switch item.origin {
        case let .event(id): sheet = .editEvent(id)
        case let .assessment(id): sheet = .editAssessment(id)
        }
    }

    func show(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast == message { toast = nil }
        }
    }

    /// Brings the main window forward. On iOS the app is its window, so
    /// there's nothing to do.
    func openMainWindow() {
        #if os(macOS)
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "WatDash" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?(id: "main")
        }
        #endif
    }
}

enum SidebarItem: Hashable {
    case today, schedule, deadlines, grades, study, importCenter
    case course(UUID)

    var title: String {
        switch self {
        case .today: "Today"
        case .schedule: "Schedule"
        case .deadlines: "Deadlines"
        case .grades: "Grades"
        case .study: "Study"
        case .importCenter: "Import"
        case .course: "Course"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .schedule: "calendar"
        case .deadlines: "flag"
        case .grades: "chart.line.uptrend.xyaxis"
        case .study: "book.closed"
        case .importCenter: "square.and.arrow.down.on.square"
        case .course: "circle.fill"
        }
    }
}

struct WatDashCommands: Commands {
    var store: AppStore
    var router: Router

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Capture…") { QuickCapture.toggle() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("New Event…") { router.sheet = .newEvent(nil) }
                .keyboardShortcut("n", modifiers: [.command])
            Button("New Assessment…") { router.sheet = .newAssessment(nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import Calendar File…") { ImportActions.pickICSFile() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Paste Quest Schedule…") { router.sheet = .questPaste }
            Button("Scan Course Folders…") { router.sheet = .courseFolders }
        }
        CommandMenu("Go") {
            Button("Today") { router.selection = .today }.keyboardShortcut("1")
            Button("Schedule") { router.selection = .schedule }.keyboardShortcut("2")
            Button("Deadlines") { router.selection = .deadlines }.keyboardShortcut("3")
            Button("Grades") { router.selection = .grades }.keyboardShortcut("4")
            Button("Study") { router.selection = .study }.keyboardShortcut("5")
            Button("Import") { router.selection = .importCenter }.keyboardShortcut("6")
            Divider()
            Button("Refresh All Sources") {
                Task { await ImportService.shared.refreshAll(); store.runEffectsNow() }
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}
