//
//  QuickCaptureView.swift
//  WatDash
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Opens quick capture: the floating panel on the Mac, a sheet on iPhone
/// and iPad.
@MainActor
enum QuickCapture {
    static func show() {
        #if os(macOS)
        QuickCapturePanel.shared.show()
        #else
        Router.shared.sheet = .quickCapture
        #endif
    }

    static func toggle() {
        #if os(macOS)
        QuickCapturePanel.shared.toggle()
        #else
        Router.shared.sheet = Router.shared.sheet == .quickCapture ? nil : .quickCapture
        #endif
    }
}

#if os(macOS)
/// The floating capture panel (⌃⌥Space from anywhere, ⌘K in the app).
/// Manual entry reduced to one line: type it, check the preview, press Return.
@MainActor
final class QuickCapturePanel {
    static let shared = QuickCapturePanel()
    private var panel: NSPanel?

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            let panel = CapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 250),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            let host = NSHostingView(rootView: QuickCaptureView(close: { [weak self] in self?.hide() })
                .environment(AppStore.shared)
                .environment(Router.shared))
            host.sizingOptions = [.preferredContentSize]
            panel.contentView = host
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - frame.height * 0.28))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickCaptureShown, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
#endif

extension Notification.Name {
    static let quickCaptureShown = Notification.Name("WatDashQuickCaptureShown")
}

struct QuickCaptureView: View {
    @Environment(AppStore.self) private var store
    var close: () -> Void

    @State private var text = ""
    @State private var result: CaptureResult?
    @State private var message: String?
    @State private var parseTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private let examples = [
        "CS 135 OH Tue 2-3pm MC 4065 weekly until Dec 4",
        "math137 quiz 4 oct 19 5:30pm",
        "A4 due fri 11:59pm",
        "Hack the North info session tomorrow 6pm @ SLC",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Palette.accent)
                    .font(.title3)
                TextField("Add anything: “CS 135 OH Tue 2–3pm MC 4065 weekly”", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit(commit)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }

            Divider()

            if let result, !text.trimmed.isEmpty {
                preview(result)
            } else if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.good)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try").font(.caption).foregroundStyle(.secondary)
                    ForEach(examples, id: \.self) { example in
                        Button(example) { text = example }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text(SmartCapture.isAvailable && store.settings.smartCapture ? "On-device model assists parsing" : parsedHere)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                #if os(macOS)
                Text("Return to add · Esc to close")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                #endif
            }
        }
        .padding(18)
        #if os(macOS)
        .frame(width: 620)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onExitCommand(perform: close)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureShown)) { _ in
            focused = true
            message = nil
        }
        .onChange(of: text) { _, newValue in reparse(newValue) }
    }

    private var parsedHere: String {
        #if os(macOS)
        "Parsed on this Mac"
        #else
        "Parsed on this device"
        #endif
    }

    @ViewBuilder
    private func preview(_ result: CaptureResult) -> some View {
        let color = store.color(for: result.courseCode)
        HStack(alignment: .top, spacing: 12) {
            KindIcon(kind: result.kind, color: result.courseCode == nil ? Palette.accentDeep : color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.title).font(.headline)
                    CourseChip(code: result.courseCode)
                }
                Group {
                    if let start = result.start {
                        if result.isAllDay {
                            Text(start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        } else if let end = result.end, end > start {
                            Text("\(start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), \(start.shortTime) – \(end.shortTime)")
                        } else {
                            Text("\(result.isAssessment || result.kind.isDue ? "Due " : "")\(start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), \(start.shortTime)")
                        }
                    } else {
                        Text("No date yet: add a day like “tue” or “oct 19”.").foregroundStyle(Palette.warn)
                    }
                }
                .font(.callout)
                HStack(spacing: 10) {
                    Label(result.kind.label, systemImage: result.kind.symbol)
                    if let location = result.location { Label(location, systemImage: "mappin") }
                    if let recurrence = result.recurrence { Label(recurrence.summary, systemImage: "repeat") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(result.confidence < 0.45 ? "Add to Inbox" : "Add") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(result.start == nil)
                if result.confidence < 0.45, result.start != nil {
                    Button("Add anyway") { commit(force: true) }
                        .linkButtonStyle()
                        .font(.caption)
                }
            }
        }
    }

    private func reparse(_ value: String) {
        message = nil
        parseTask?.cancel()
        let now = Date.now
        let known = store.knownCourseCodes
        result = QuickCaptureParser.parse(value, now: now, knownCourses: known)
        guard store.settings.smartCapture, SmartCapture.isAvailable, !value.trimmed.isEmpty else { return }
        parseTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let smart = await SmartCapture.parse(value, now: now, knownCourses: known)
            guard !Task.isCancelled, text == value else { return }
            result = smart
        }
    }

    private func commit() { commit(force: false) }

    private func commit(force: Bool) {
        guard let result, result.start != nil else { return }
        message = ImportService.shared.add(result, forceConfirm: force)
        text = ""
        self.result = nil
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if text.isEmpty { close() }
        }
    }
}
