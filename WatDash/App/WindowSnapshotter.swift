//
//  WindowSnapshotter.swift
//  WatDash
//

#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders each screen of the main window to PNGs and quits.
///
///     WatDash.app/Contents/MacOS/WatDash -WatDashDemo -WatDashSnapshot /tmp/shots
///
/// Uses the window's own view hierarchy (cacheDisplay), so it needs no Screen
/// Recording permission — handy for checking layouts from a script.
@MainActor
enum WindowSnapshotter {
    static func say(_ message: String) {
        FileHandle.standardError.write(Data("snapshot: \(message)\n".utf8))
    }

    static func run(outputDirectory: URL) {
        say("starting")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let router = Router.shared
            if !NSApp.windows.contains(where: { $0.frame.width > 600 }) {
                router.openMainWindow()
                try? await Task.sleep(for: .seconds(2))
            }
            let store = AppStore.shared
            var screens: [(String, SidebarItem)] = [
                ("today", .today), ("schedule", .schedule), ("deadlines", .deadlines),
                ("grades", .grades), ("study", .study), ("import", .importCenter),
            ]
            if let course = store.courses.first(where: { !$0.scheme.components.isEmpty }) {
                screens.append(("course", .course(course.id)))
            }
            say("windows = \(NSApp.windows.map { "\($0.className) \($0.frame) visible=\($0.isVisible)" })")
            if let window = NSApp.windows.first(where: { $0.contentView != nil && $0.frame.width > 600 }) {
                window.setContentSize(NSSize(width: 1360, height: 880))
                for (name, item) in screens {
                    router.selection = item
                    try? await Task.sleep(for: .milliseconds(900))
                    capture(window, to: outputDirectory.appendingPathComponent("\(name).png"))
                }
                router.sheet = .dashboardGallery
                try? await Task.sleep(for: .milliseconds(800))
                if let sheet = window.attachedSheet { capture(sheet, to: outputDirectory.appendingPathComponent("gallery.png")) }
                router.sheet = nil
                try? await Task.sleep(for: .milliseconds(500))
                let quiz = store.assessments.first(where: { $0.kind == .quiz && !$0.isGraded && $0.coverage != nil }) ?? store.assessments.first(where: { $0.kind == .quiz && !$0.isGraded })
                router.sheet = .studyPrompt(quiz?.courseCode ?? "", quiz?.id)
                try? await Task.sleep(for: .milliseconds(800))
                if let sheet = window.attachedSheet { capture(sheet, to: outputDirectory.appendingPathComponent("study-prompt.png")) }
                router.sheet = nil
            }
            QuickCapturePanel.shared.show()
            try? await Task.sleep(for: .milliseconds(800))
            if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
                capture(panel, to: outputDirectory.appendingPathComponent("capture.png"))
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            do { try data.write(to: url); say("wrote \(url.lastPathComponent)") } catch { say("write failed \(url.path) \(error)") }
        } else {
            say("no png for \(url.lastPathComponent) \(bounds)")
        }
    }
}
#endif
