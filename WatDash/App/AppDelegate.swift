//
//  AppDelegate.swift
//  WatDash
//

import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var snapshotTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppStore.shared
        let arguments = ProcessInfo.processInfo.arguments
        // Screenshot runs must not pop permission prompts or grab the hotkey.
        let snapshotRun = arguments.contains("-WatDashSnapshot")

        if store.isDemo, store.courses.isEmpty {
            store.replaceAll(with: DemoSeeder.sampleTerm())
        }

        // Projections: every commit (debounced) refreshes these.
        store.effects = snapshotRun ? [] : [
            { SnapshotWriter.write(from: $0) },
            { NotificationScheduler.shared.reconcile(store: $0) },
            { CalendarSync.shared.scheduleExport($0) },
        ]
        store.runEffectsNow()

        // "Up next" moves with the clock, not just with edits.
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in SnapshotWriter.write(from: AppStore.shared) }
        }

        if store.settings.quickCaptureHotKey && !snapshotRun {
            HotKey.shared.register { QuickCapturePanel.shared.toggle() }
        }
        if (store.settings.notifyDeadlines || store.settings.notifyClasses) && !snapshotRun {
            Task { await NotificationScheduler.shared.requestAuthorization() }
        }
        CalendarSync.shared.observeChanges {
            for source in AppStore.shared.sources where source.kind == .appleCalendar {
                CalendarSync.shared.importEvents(source: source, into: AppStore.shared)
            }
        }

        if !snapshotRun {
            ImportService.shared.startRefreshing()
            Task { await ImportService.shared.refreshAll() }
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
        for url in urls {
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
                case "capture": QuickCapturePanel.shared.show()
                case "grades": Router.shared.selection = .grades
                case "deadlines": Router.shared.selection = .deadlines
                case "schedule": Router.shared.selection = .schedule
                default: Router.shared.selection = .today
                }
            }
        }
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
