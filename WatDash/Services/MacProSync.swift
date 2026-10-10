//
//  MacProSync.swift
//  WatDash
//

#if os(macOS)
import AppKit
import Foundation
import Observation

/// Keeps the Mac Pro's Syllabus in step with WatDash, both ways, through the
/// classes repository on GitHub:
///
/// 1. Pull WatDash's own clone (`MacProRepo`).
/// 2. Apply each note the Mac Pro left in `Inbox/`: `done:` and `undone:`
///    set an assessment's tick; `capture:` goes through quick capture, so an
///    unsure one waits in WatDash's inbox as usual.
/// 3. Export the calendar (`MacProExport`) to `Calendar/watdash.json`, with
///    what became of each note, delete the applied notes, commit, push.
///
/// Runs a few seconds after the store changes, every five minutes (notes
/// from the Mac Pro, and the window moving on a day), on wake, and from
/// Settings. Only the real store syncs: never the sample term or a scratch
/// file.
@MainActor
@Observable
final class MacProSync {
    static let shared = MacProSync()

    private(set) var lastPushed: Date?
    private(set) var lastCheck: Date?
    private(set) var lastError: String?
    private(set) var isRunning = false
    private(set) var remote: String?

    @ObservationIgnored private var store: AppStore?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var notes: [MacProExport.NoteLog] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastOfficeHours: Bool?
    /// The round-trip test points the sync at a local repository and clone.
    @ObservationIgnored private var testRemote: String?
    @ObservationIgnored private var testClone: URL?

    static let pollInterval: TimeInterval = 5 * 60

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatDash/MacPro", isDirectory: true)
    }
    private var cloneURL: URL { testClone ?? folder.appendingPathComponent("Study", isDirectory: true) }
    private var stateURL: URL { (testClone?.deletingLastPathComponent() ?? folder).appendingPathComponent("state.json") }

    // MARK: - Lifecycle

    func start(store: AppStore) {
        self.store = store
        guard timer == nil else { return schedule(after: 5) }
        loadState()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor in MacProSync.shared.schedule(after: 0) }
        }
        timer?.tolerance = 30
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                // Wi-Fi takes a moment to come back after sleep.
                Task { @MainActor in MacProSync.shared.schedule(after: 30) }
            },
            // The office-hours switch is a view preference, not store data.
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    let on = OfficeHoursLayer.isOn
                    if let last = MacProSync.shared.lastOfficeHours, last != on { MacProSync.shared.schedule(after: 3) }
                }
            },
        ]
        schedule(after: 5)
    }

    /// Every store commit lands here (debounced by the store, then again here).
    func storeChanged(_ store: AppStore) {
        self.store = store
        schedule(after: 10)
    }

    func syncNow() {
        schedule(after: 0)
    }

    private func schedule(after seconds: Double) {
        guard let store, store.settings.macProSync || testRemote != nil else { return }
        if isRunning {
            runAgain = true
            return
        }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard let self, !Task.isCancelled else { return }
            await self.cycle()
        }
    }

    /// Debug builds: one cycle against `remote` in `clone`, then `done`.
    func runOnceForTest(store: AppStore, remote: String, clone: URL, done: @escaping (String) -> Void) {
        self.store = store
        testRemote = remote
        testClone = clone
        loadState()
        Task {
            await cycle()
            done(lastError ?? "ok: pushed \(lastPushed.map { MacProExport.stamp($0) } ?? "nothing")")
        }
    }

    // MARK: - One pass

    private func cycle() async {
        guard let store, !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            if runAgain {
                runAgain = false
                schedule(after: 2)
            }
        }
        do {
            let remote = try await resolveRemote(store)
            self.remote = remote
            let repo = MacProRepo(directory: cloneURL, remote: remote)
            let (inbox, current) = try await Task.detached {
                try repo.prepare()
                try repo.pull()
                return (repo.inbox(), repo.currentExport())
            }.value

            var consumed: [String] = []
            for file in inbox {
                consumed.append(file.path)
                // A note applied before a push failed is still remembered: it
                // is deleted again, never applied twice.
                if notes.contains(where: { $0.file == file.path }) { continue }
                notes.append(await apply(file.path, file.text, store: store))
                saveState()
            }
            notes = Array(notes.suffix(200))

            let now = Date()
            let officeHours = OfficeHoursLayer.isOn
            lastOfficeHours = officeHours
            let input = MacProExport.Input(
                courses: store.courses, events: store.events, assessments: store.assessments,
                termName: store.settings.termName, termEnd: store.settings.termEnd,
                classesFolder: store.settings.classesFolderPath, officeHours: officeHours,
                palette: Palette.courses, notes: notes.filter { recent($0, now: now) }, now: now)
            var document = MacProExport.document(input, exported: MacProExport.stamp(now))
            if let current, let previous = MacProExport.decode(current), MacProExport.sameContent(previous, document) {
                document.exported = previous.exported
            }
            let data = try MacProExport.encode(document)
            if data != current || !consumed.isEmpty {
                let applied = consumed.count
                let message = applied == 0 ? "Calendar from WatDash"
                    : "Calendar from WatDash, with \(applied) note\(applied == 1 ? "" : "s") from the Mac Pro"
                let pushed = try await Task.detached { try repo.publish(export: data, consumed: consumed, message: message) }.value
                if pushed { lastPushed = .now }
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.network.error("Mac Pro sync: \(error.localizedDescription, privacy: .public)")
        }
        lastCheck = .now
        saveState()
    }

    private func recent(_ note: MacProExport.NoteLog, now: Date) -> Bool {
        guard let when = MacProExport.date(fromStamp: note.when) else { return true }
        return now.timeIntervalSince(when) < 30 * 86_400
    }

    private func apply(_ path: String, _ text: String, store: AppStore) async -> MacProExport.NoteLog {
        let when = MacProExport.stamp(.now)
        let summary = MacProInbox.summary(text)
        func log(_ result: String, _ message: String) -> MacProExport.NoteLog {
            Log.network.info("Mac Pro note \(path, privacy: .public): \(result, privacy: .public)")
            return MacProExport.NoteLog(file: path, note: summary, result: result, message: message, when: when)
        }
        guard let note = MacProInbox.parse(text) else {
            return log("unreadable", "WatDash couldn't read this note.")
        }
        switch note.action {
        case let .done(id), let .undone(id):
            var isDone = false
            if case .done = note.action { isDone = true }
            guard let index = MacProInbox.assessmentIndex(forExportID: id, in: store.assessments) else {
                return log("unknown", "WatDash has nothing with this id any more.")
            }
            var assessment = store.assessments[index]
            assessment.isDone = isDone
            store.updateAssessment(assessment)
            return log("applied", "\(assessment.courseCode) \(assessment.title) marked \(isDone ? "done" : "not done").")
        case let .capture(line):
            let base = note.written ?? .now
            let capture = store.settings.smartCapture
                ? await SmartCapture.parse(line, now: base, knownCourses: store.knownCourseCodes)
                : QuickCaptureParser.parse(line, now: base, knownCourses: store.knownCourseCodes)
            let (message, outcome) = ImportService.shared.addReporting(capture)
            switch outcome {
            case .added: return log("applied", message)
            case .proposed: return log("inbox", message)
            case .undated: return log("failed", message)
            }
        }
    }

    /// The repository to sync: Settings, else the classes folder's own
    /// `origin`, else the test's.
    private func resolveRemote(_ store: AppStore) async throws -> String {
        if let testRemote { return testRemote }
        if let chosen = store.settings.macProRemote.trimmed.nilIfEmpty { return chosen }
        let classes = URL(fileURLWithPath: store.settings.classesFolderPath)
        let found = await Task.detached {
            MacProRepo(directory: classes, remote: "").run(["remote", "get-url", "origin"], timeout: 15).output.trimmed
        }.value
        guard !found.isEmpty, !found.contains("\n"), !found.hasPrefix("error"), !found.hasPrefix("fatal") else {
            throw MacProRepo.Failure(summary: "The classes folder has no GitHub remote to sync through.")
        }
        return found
    }

    // MARK: - Status

    /// "Mac Pro sync: last pushed today at 2:03 PM", or what went wrong.
    var statusLine: String {
        if isRunning { return "Mac Pro sync: syncing…" }
        if let lastError { return "Mac Pro sync: \(lastError)" }
        guard let lastPushed else {
            return lastCheck == nil ? "Mac Pro sync: not run yet" : "Mac Pro sync: up to date, nothing pushed yet"
        }
        let time = lastPushed.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(lastPushed) ? "today" : lastPushed.formatted(date: .abbreviated, time: .omitted)
        return "Mac Pro sync: last pushed \(day) at \(time)"
    }

    // MARK: - State

    private struct State: Codable {
        var lastPushed: Date?
        var lastCheck: Date?
        var lastError: String?
        var notes: [MacProExport.NoteLog] = []
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(State.self, from: data) else { return }
        lastPushed = state.lastPushed
        lastCheck = state.lastCheck
        lastError = state.lastError
        notes = state.notes
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let state = State(lastPushed: lastPushed, lastCheck: lastCheck, lastError: lastError, notes: notes)
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        } catch {
            Log.network.error("Mac Pro sync state not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
