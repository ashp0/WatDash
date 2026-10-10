//
//  AppDelegate.swift
//  WatDash
//

import SwiftUI
#if os(macOS)
import AppKit
import ServiceManagement
#endif

/// Launch work both platforms share: the projections every commit runs, the
/// refresh loop, Apple Calendar observation and the reminder permission.
@MainActor
enum AppLaunch {
    /// `isolated`: a screenshot run or a scratch store, which must not reach
    /// the widgets, reminders or calendars shared with the installed app.
    static func start(isolated: Bool, refreshes: Bool) {
        let store = AppStore.shared
        if store.isDemo, store.courses.isEmpty {
            store.replaceAll(with: DemoSeeder.sampleTerm())
        }

        // Projections: every commit (debounced) refreshes these.
        var effects: [(AppStore) -> Void] = [
            { SnapshotWriter.write(from: $0) },
            { NotificationScheduler.shared.reconcile(store: $0) },
            { CalendarSync.shared.scheduleExport($0) },
        ]
        #if os(macOS)
        // The Mac Pro gets the real term only, never the sample one.
        let syncsMacPro = !isolated && !store.isDemo
        if syncsMacPro {
            effects.append { MacProSync.shared.storeChanged($0) }
            effects.append { store in
                FolderWatcher.shared.watch(store.settings.classesFolderPath) { ImportService.shared.refreshCourseFolders() }
            }
        }
        #endif
        store.effects = isolated ? [] : effects
        store.runEffectsNow()
        #if os(macOS)
        if syncsMacPro { MacProSync.shared.start(store: store) }
        #endif

        if (store.settings.notifyDeadlines || store.settings.notifyClasses) && !isolated {
            Task { await NotificationScheduler.shared.requestAuthorization() }
        }
        CalendarSync.shared.observeChanges {
            for source in AppStore.shared.sources where source.kind == .appleCalendar {
                CalendarSync.shared.importEvents(source: source, into: AppStore.shared)
            }
        }

        if refreshes {
            ImportService.shared.startRefreshing()
            Task { await ImportService.shared.refreshAll() }
        }
    }

    /// Opened .ics files and watdash:// links.
    static func open(_ url: URL) {
        if url.isFileURL, url.pathExtension.lowercased() == "ics" {
            do {
                let summary = try ImportService.shared.importICSFile(url)
                Router.shared.show("\(summary.title): \(summary.detail)")
                Router.shared.selection = .schedule
            } catch {
                Router.shared.show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        } else if url.scheme == SharedConstants.urlScheme {
            switch url.host() {
            case "capture": QuickCapture.show()
            case "grades": Router.shared.selection = .grades
            case "deadlines": Router.shared.selection = .deadlines
            case "schedule": Router.shared.selection = .schedule
            default: Router.shared.selection = .today
            }
        }
    }
}

#if os(macOS)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var snapshotTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppStore.shared
        let arguments = ProcessInfo.processInfo.arguments
        // Screenshot runs must not pop permission prompts or grab the hotkey,
        // and a scratch store must not reach the widgets, reminders or
        // calendars it shares with the installed app.
        let snapshotRun = arguments.contains("-WatDashSnapshot")
        let isolated = snapshotRun || store.isScratch

        AppLaunch.start(isolated: isolated, refreshes: !snapshotRun)

        // "Up next" moves with the clock, not just with edits.
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in SnapshotWriter.write(from: AppStore.shared) }
        }

        if store.settings.quickCaptureHotKey && !isolated {
            HotKey.shared.register { QuickCapturePanel.shared.toggle() }
        }

        #if DEBUG
        if arguments.contains("-WatDashScanFolders") {
            let scans = ImportService.shared.scanCourseFolders()
            let summary = ImportService.shared.importCourseFolders(scans)
            FileHandle.standardError.write(Data("import: \(summary.title) — \(summary.detail)\n".utf8))
            Task {
                let holidays = try? await ImportService.shared.importHolidays()
                FileHandle.standardError.write(Data("import: \(holidays?.detail ?? "holidays failed")\n".utf8))
            }
        }
        if let index = arguments.firstIndex(of: "-WatDashSnapshot"), index + 1 < arguments.count {
            WindowSnapshotter.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1]))
        }
        // The Mac Pro round trip (Syllabus's `make roundtrip`): one sync
        // against a local repository, with a scratch store, then quit.
        if let index = arguments.firstIndex(of: "-WatDashMacProTest"), index + 2 < arguments.count, store.isScratch {
            MacProSync.shared.runOnceForTest(store: store, remote: arguments[index + 1],
                                             clone: URL(fileURLWithPath: arguments[index + 2])) { result in
                store.saveNow()
                FileHandle.standardError.write(Data("macpro: \(result)\n".utf8))
                exit(result.hasPrefix("ok") ? 0 : 1)
            }
        }
        #endif
        Log.lifecycle.info("Launched with \(store.courses.count) courses, \(store.events.count) events")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The menu bar extra keeps working with the window closed.
        !AppStore.shared.settings.showMenuBarExtra
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.saveNow()
    }

    /// Double-clicked .ics files and watdash:// links.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppLaunch.open(url) }
        Router.shared.openMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Router.shared.openMainWindow() }
        return true
    }
}

/// Launch at login through the modern ServiceManagement API.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.lifecycle.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#else
/// iPhone and iPad. Opened files and links arrive through the scene's
/// onOpenURL instead (see WatDashApp).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let store = AppStore.shared
        AppLaunch.start(isolated: store.isScratch, refreshes: true)
        Log.lifecycle.info("Launched with \(store.courses.count) courses, \(store.events.count) events")
        return true
    }
}
#endif
