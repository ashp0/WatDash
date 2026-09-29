//
//  WatDashApp.swift
//  WatDash
//

import SwiftUI

@main
struct WatDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared
    @State private var router = Router.shared

    var body: some Scene {
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
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
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

    enum Sheet: Identifiable, Equatable {
        case questPaste, outline(URL), courseFolders, feed, appleCalendar, openData, dashboardGallery
        case newEvent(Date?), editEvent(String), newAssessment(String?), editAssessment(UUID), studyPrompt(String, UUID?)
        case courseEditor(UUID), inbox

        var id: String {
            switch self {
            case .questPaste: "quest"
            case let .outline(url): "outline-\(url.path)"
            case .courseFolders: "folders"
            case .feed: "feed"
            case .appleCalendar: "apple"
            case .openData: "opendata"
            case .dashboardGallery: "gallery"
            case let .newEvent(date): "new-event-\(date?.timeIntervalSince1970 ?? 0)"
            case let .editEvent(id): "event-\(id)"
            case let .newAssessment(code): "new-assessment-\(code ?? "")"
            case let .editAssessment(id): "assessment-\(id)"
            case let .studyPrompt(code, id): "study-\(code)-\(id?.uuidString ?? "")"
            case let .courseEditor(id): "course-\(id)"
            case .inbox: "inbox"
            }
        }
    }

    func show(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast == message { toast = nil }
        }
    }

    func openMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "WatDash" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?(id: "main")
        }
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
            Button("Quick Capture…") { QuickCapturePanel.shared.toggle() }
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
