//
//  FolderWatcher.swift
//  WatDash
//

#if os(macOS)
import CoreServices
import Foundation

/// Watches the classes folder for a course's `CLAUDE.md` changing (Claude
/// edits them all the time: dates, rooms, marks) and re-imports the course
/// folders a couple of seconds later. Before this, an edit waited for the
/// hourly refresh or a click on Refresh.
///
/// FSEvents, file-level, on the whole folder: editors save by writing a new
/// file and renaming it over the old one, which a watch on the file itself
/// would lose.
@MainActor
final class FolderWatcher {
    static let shared = FolderWatcher()

    private var stream: FSEventStreamRef?
    private(set) var path: String?
    private var handler: (() -> Void)?
    private var pending: Task<Void, Never>?

    func watch(_ folder: String, onChange: @escaping () -> Void) {
        let standardized = (folder as NSString).standardizingPath
        handler = onChange
        guard standardized != path || stream == nil else { return }
        stop()
        path = standardized
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            Task { @MainActor in watcher.changed(Array(list.prefix(count))) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, [standardized] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else {
            Log.importer.error("Couldn't watch \(standardized, privacy: .public)")
            return
        }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        path = nil
    }

    /// Only a course's own CLAUDE.md (one folder down) counts.
    static func isCourseManifest(_ changed: String, root: String) -> Bool {
        let parent = (changed as NSString).deletingLastPathComponent
        return (changed as NSString).lastPathComponent == "CLAUDE.md"
            && (parent as NSString).deletingLastPathComponent == root
    }

    private func changed(_ paths: [String]) {
        guard let root = path, paths.contains(where: { Self.isCourseManifest(($0 as NSString).standardizingPath, root: root) }) else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            Log.importer.info("A course CLAUDE.md changed; re-reading the course folders")
            self.handler?()
        }
    }
}
#endif
