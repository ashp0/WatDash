//
//  MenuBarView.swift
//  WatDash
//

import SwiftUI

/// Menu bar icon: shows a countdown to the next class when one is close.
struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let next = store.nowAndNext().next
        Group {
            if let next, next.start.timeIntervalSince(store.now) < 90 * 60 {
                Label("\(next.courseCode ?? next.title) \(next.start.compactCountdown(from: store.now))", systemImage: "graduationcap.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "graduationcap.fill")
            }
        }
        .onAppear { Router.shared.openWindowAction = openWindow }
    }
}

/// The menu bar panel: now/next, today's remaining items, what's due and a
/// capture field. Grades stay on the Grades screen and the sidebar.
struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var captureText = ""
    @State private var feedback: String?

    var body: some View {
        let (current, next) = store.nowAndNext()
        let today = store.agenda(on: store.now).filter { $0.end >= store.now }
        let due = Array(store.upcomingDeadlines(days: 7).prefix(4))
        VStack(alignment: .leading, spacing: 12) {
            Text(store.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.headline)

            if let current {
                block(label: "NOW", item: current, trailing: "until \(current.end.shortTime)")
            }
            if let next {
                block(label: "NEXT", item: next, trailing: "in \(next.start.compactCountdown(from: store.now))")
            }

            if !today.isEmpty {
                Divider()
                Text("Rest of today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(today.prefix(5)) { AgendaRow(item: $0) }
            }

            if !due.isEmpty {
                Divider()
                Text("Due this week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(due) { AgendaRow(item: $0, showDate: true, showCountdown: true) }
            }

            Divider()
            HStack {
                Image(systemName: "bolt").foregroundStyle(Palette.accent)
                TextField("Quick add: “A4 due fri 11:59pm”", text: $captureText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let result = QuickCaptureParser.parse(captureText, now: .now, knownCourses: store.knownCourseCodes)
                        feedback = ImportService.shared.add(result)
                        captureText = ""
                    }
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Open WatDash") { router.openMainWindow() }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless)
                    .help("Quit WatDash")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360)
    }

    private func block(label: String, item: AgendaItem, trailing: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(store.color(for: item.courseCode)).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text([item.start.shortTime, item.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Palette.accentDeep)
        }
    }
}
