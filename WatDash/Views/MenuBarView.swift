//
//  MenuBarView.swift
//  WatDash
//

#if os(macOS)
import SwiftUI

/// Menu bar icon and its one line (see `MenuBarStatus`).
///
/// The status is computed in the App's scene body and passed in, rather than
/// read from the store in here, so the label is rebuilt whenever the scene
/// is: the menu bar item is not an ordinary view hierarchy.
struct MenuBarLabel: View {
    var status: MenuBarStatus.Status
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if status.text.isEmpty {
                Image(systemName: status.symbol)
            } else {
                Label(status.text, systemImage: status.symbol)
                    .labelStyle(.titleAndIcon)
            }
        }
        .onAppear { Router.shared.openWindowAction = openWindow }
    }
}

/// The menu bar panel, in Today's spirit: the one thing that matters now,
/// what else is due soon, what's left of the day, and a capture field.
struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(OfficeHoursLayer.key) private var showOfficeHours = false
    @State private var captureText = ""
    @State private var feedback: String?

    var body: some View {
        let now = store.now
        let status = store.menuBarStatus(officeHours: showOfficeHours)
        let leadID = status.item?.id
        let dueSoon = store.focus().filter { $0.id != leadID }.prefix(3)
        let laterToday = store.agenda(on: now)
            .filter { MenuBarStatus.isAttended($0, officeHours: showOfficeHours) && $0.start > now && $0.id != leadID }
            .prefix(3)

        VStack(alignment: .leading, spacing: 14) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            MenuBarLead(status: status)

            if !dueSoon.isEmpty {
                section("Due soon") {
                    ForEach(dueSoon) { entry in
                        HStack(spacing: 8) {
                            DoneCheckbox(item: entry.item)
                            AgendaRow(item: entry.item, showDate: true, showCountdown: true)
                        }
                    }
                }
            }
            if !laterToday.isEmpty {
                section("Later today") {
                    ForEach(laterToday) { AgendaRow(item: $0) }
                }
            }

            captureField

            HStack {
                Button("Open WatDash") { router.openMainWindow() }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless)
                    .help("Quit WatDash")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var captureField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Palette.accent)
                TextField("Add: “A4 due fri 11:59pm”", text: $captureText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let result = QuickCaptureParser.parse(captureText, now: .now, knownCourses: store.knownCourseCodes)
                        feedback = ImportService.shared.add(result)
                        captureText = ""
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The menu bar's line, large: what it is, and how long is left.
private struct MenuBarLead: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var status: MenuBarStatus.Status

    var body: some View {
        if let item = status.item {
            let color = store.color(for: item.courseCode)
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(status.reason == .urgent ? Palette.warn : .secondary)
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text([item.courseCode, item.kind.label, item.location].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(countdown(item))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(status.reason == .urgent ? Palette.warn : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                router.openMainWindow()
                router.open(item)
            }
        } else {
            Label("Nothing due in the next three weeks", systemImage: "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(Palette.good)
        }
    }

    private var caption: String {
        switch status.reason {
        case .inClass: "Now"
        case .startingSoon: "Starting soon"
        case .urgent: status.symbol == "exclamationmark.triangle" ? "Late" : "Most urgent"
        case .nextDue: "Next due"
        case .clear: ""
        }
    }

    private func countdown(_ item: AgendaItem) -> String {
        let now = store.now
        switch status.reason {
        case .inClass: return "\(item.end.compactCountdown(from: now)) left"
        case .urgent where Urgency.dueDate(item) <= now: return "late"
        default: return Urgency.dueDate(item).compactCountdown(from: now)
        }
    }
}
#endif
