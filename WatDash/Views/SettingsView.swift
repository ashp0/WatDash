//
//  SettingsView.swift
//  WatDash
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            GradeSettings().tabItem { Label("Grades", systemImage: "percent") }
            CalendarSettings().tabItem { Label("Calendar", systemImage: "calendar") }
            NotificationSettings().tabItem { Label("Reminders", systemImage: "bell") }
            IntegrationSettings().tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

/// Binding into one settings field, committed through the store.
@MainActor
private func setting<V>(_ store: AppStore, _ keyPath: WritableKeyPath<AppSettings, V>) -> Binding<V> {
    Binding(
        get: { store.settings[keyPath: keyPath] },
        set: { value in
            var settings = store.settings
            settings[keyPath: keyPath] = value
            store.settings = settings
        }
    )
}

struct GeneralSettings: View {
    @Environment(AppStore.self) private var store
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Term") {
                TextField("Name", text: setting(store, \.termName))
                TextField("Quest term code", text: setting(store, \.termCode))
                DatePicker("Classes start", selection: setting(store, \.termStart), displayedComponents: .date)
                DatePicker("Exams end", selection: setting(store, \.termEnd), displayedComponents: .date)
            }
            Section("Course folders") {
                LabeledContent("Classes folder") {
                    HStack {
                        Text(store.settings.classesFolderPath).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url {
                                setting(store, \.classesFolderPath).wrappedValue = url.path
                            }
                        }
                    }
                }
            }
            Section("App") {
                Toggle("Show in menu bar", isOn: setting(store, \.showMenuBarExtra))
                Toggle("Quick capture shortcut ⌃⌥Space (works in any app)", isOn: Binding(
                    get: { store.settings.quickCaptureHotKey },
                    set: { on in
                        setting(store, \.quickCaptureHotKey).wrappedValue = on
                        if on { HotKey.shared.register { QuickCapturePanel.shared.toggle() } } else { HotKey.shared.unregister() }
                    }
                ))
                Toggle("Use the on-device model to read messy captures", isOn: setting(store, \.smartCapture))
                Text(SmartCapture.availabilityNote).font(.caption).foregroundStyle(.secondary)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
                Picker("Refresh feeds and folders", selection: setting(store, \.feedRefreshMinutes)) {
                    Text("Every 15 minutes").tag(15.0)
                    Text("Every hour").tag(60.0)
                    Text("Every 6 hours").tag(360.0)
                }
            }
            Section("Data") {
                LabeledContent("Stored at", value: store.fileURL.path)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                    Button("Load Sample Term…") { store.replaceAll(with: DemoSeeder.sampleTerm()) }
                    Button("Erase Everything…", role: .destructive) { store.replaceAll(with: AppData()) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GradeSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section {
                LabeledContent("Target average") {
                    HStack {
                        Slider(value: setting(store, \.targetAverage), in: 60...95, step: 1)
                        Text("\(Int(store.settings.targetAverage))%").monospacedDigit().frame(width: 40)
                    }
                }
                Text("80% is the cumulative average the Faculty of Math asks for before a sixth course.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Round course grades like the transcript", isOn: setting(store, \.roundCourseGrades))
            }
            Section("Earlier terms (for the cumulative average)") {
                TextField("Units completed", value: setting(store, \.previousUnits), format: .number)
                TextField("Cumulative average so far", value: Binding(
                    get: { store.settings.previousAverage },
                    set: { setting(store, \.previousAverage).wrappedValue = $0 }
                ), format: .number)
                Text("Leave at 0 in your first term: your cumulative average is this term's average.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Projection") {
                LabeledContent("Exams vs coursework") {
                    HStack {
                        Slider(value: setting(store, \.examGap), in: 0...20, step: 0.5)
                        Text("−\(store.settings.examGap.oneDecimal)").monospacedDigit().frame(width: 44)
                    }
                }
                Toggle("Learn this gap from my own marks once there are some", isOn: setting(store, \.learnExamGap))
                Text("Currently using \(store.effectiveExamGap.oneDecimal) points. Early-term averages flatter you because heavily weighted exams come later; this corrects for it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct CalendarSettings: View {
    @Environment(AppStore.self) private var store
    @State private var status = CalendarSync.shared.lastExportSummary

    var body: some View {
        Form {
            Section {
                Toggle("Keep WatDash calendars in Apple Calendar", isOn: Binding(
                    get: { store.settings.exportToAppleCalendar },
                    set: { on in
                        Task {
                            if on, !CalendarSync.shared.hasAccess { _ = await CalendarSync.shared.requestAccess() }
                            setting(store, \.exportToAppleCalendar).wrappedValue = on && CalendarSync.shared.hasAccess
                            if on { CalendarSync.shared.export(store); status = CalendarSync.shared.lastExportSummary }
                        }
                    }
                ))
                Text("Creates “\(CalendarSync.classesTitle)” and “\(CalendarSync.deadlinesTitle)” (in iCloud when available) so your phone and watch see the same term. WatDash only ever edits events it created.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Classes, office hours and events", isOn: setting(store, \.exportClasses))
                Toggle("Deadlines, quizzes and exams", isOn: setting(store, \.exportDeadlines))
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Sync Now") { CalendarSync.shared.export(store); status = CalendarSync.shared.lastExportSummary }
                        .disabled(!store.settings.exportToAppleCalendar)
                    Button("Remove WatDash Calendars", role: .destructive) { CalendarSync.shared.removeOwnCalendars(store) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct NotificationSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Deadlines, quizzes and exams") {
                Toggle("Remind me", isOn: Binding(
                    get: { store.settings.notifyDeadlines },
                    set: { on in
                        setting(store, \.notifyDeadlines).wrappedValue = on
                        if on { Task { await NotificationScheduler.shared.requestAuthorization() } }
                    }
                ))
                Toggle("A day before", isOn: leadBinding(24))
                Toggle("Two hours before", isOn: leadBinding(2))
                Toggle("Thirty minutes before", isOn: leadBinding(0.5))
            }
            Section("Classes") {
                Toggle("Remind me before each class", isOn: Binding(
                    get: { store.settings.notifyClasses },
                    set: { on in
                        setting(store, \.notifyClasses).wrappedValue = on
                        if on { Task { await NotificationScheduler.shared.requestAuthorization() } }
                    }
                ))
                Stepper("\(Int(store.settings.classLeadMinutes)) minutes before", value: setting(store, \.classLeadMinutes), in: 5...60, step: 5)
                Text("For alarms that ring through silent mode on your phone, WatAlarm does this on iOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func leadBinding(_ hours: Double) -> Binding<Bool> {
        Binding(
            get: { store.settings.deadlineLeadHours.contains(hours) },
            set: { on in
                var leads = Set(store.settings.deadlineLeadHours)
                if on { leads.insert(hours) } else { leads.remove(hours) }
                setting(store, \.deadlineLeadHours).wrappedValue = leads.sorted(by: >)
            }
        )
    }
}

struct IntegrationSettings: View {
    @State private var openDataKey = Keychain.get(.openData) ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Waterloo Open Data") {
                SecureField("API key", text: $openDataKey)
                HStack {
                    Button("Save to Keychain") { saved = Keychain.set(openDataKey, for: .openData) }
                    Link("Get a free key", destination: OpenDataClient.registrationPage)
                    if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good) }
                }
                Text("Unlocks class times, important dates, final exam slots, seat counts and campus events. Holidays work without a key.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude Code") {
                Text("Study pages are made by Claude Code on your subscription, not through the API: WatDash builds the prompt (Study → Claude Code Prompt…) and you paste it in. No API key is stored.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
