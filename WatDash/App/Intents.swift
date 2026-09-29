//
//  Intents.swift
//  WatDash
//

import AppIntents
import Foundation

/// Shortcuts, Siri and Spotlight actions. They run in the app's process and
/// share the store, so "Add to WatDash" from Spotlight goes through exactly
/// the same parser and inbox rules as the capture panel.
struct AddToWatDashIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to WatDash"
    static let description = IntentDescription("Adds a class, deadline or event from one line of text, like “A4 due fri 11:59pm”.")

    @Parameter(title: "Text", requestValueDialog: "What should I add?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to WatDash")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let result = await SmartCapture.parse(text, now: .now, knownCourses: store.knownCourseCodes)
        let message = ImportService.shared.add(result)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription("Tells you the class you're in and what's coming next.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let (current, next) = store.nowAndNext()
        var parts: [String] = []
        if let current {
            parts.append("You're in \(current.title) until \(current.end.shortTime).")
        }
        if let next {
            let place = next.location.map { " in \($0)" } ?? ""
            parts.append("Next: \(next.title), \(next.start.relativeDayLabel.lowercased()) at \(next.start.shortTime)\(place).")
        }
        if parts.isEmpty { parts.append("Nothing on your timetable.") }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}

struct DueThisWeekIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Due This Week"
    static let description = IntentDescription("Lists assignments, quizzes and exams in the next seven days.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        let items = AppStore.shared.upcomingDeadlines(days: 7)
        let lines = items.map { item in
            "\(item.courseCode.map { "\($0) " } ?? "")\(item.title) — \(item.start.relativeDayLabel) \(item.start.shortTime)"
        }
        let dialog = lines.isEmpty ? "Nothing due in the next week." : lines.joined(separator: "\n")
        return .result(value: lines, dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct OverloadStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Overload Status"
    static let description = IntentDescription("Your projected average against the 80% line for a sixth course.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let term = AppStore.shared.term
        guard let projected = term.projected, let margin = term.margin else {
            return .result(dialog: "WatDash needs grading schemes and a few marks before it can project your average.")
        }
        let direction = margin >= 0 ? "above" : "below"
        let chance = term.probabilityAtLeastTarget.map { " About a \(Int(($0 * 100).rounded()))% chance of finishing at \(Int(term.target)) or higher." } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: "Projected \(projected.oneDecimal), \(abs(margin).oneDecimal) points \(direction) your \(Int(term.target))% target.\(chance)"))
    }
}

struct OpenQuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Capture"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCapture.show()
        return .result()
    }
}

struct WatDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToWatDashIntent(), phrases: ["Add to \(.applicationName)", "Capture in \(.applicationName)"],
                    shortTitle: "Add to WatDash", systemImageName: "bolt")
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next in \(.applicationName)", "What's my next class in \(.applicationName)"],
                    shortTitle: "What's Next", systemImageName: "clock")
        AppShortcut(intent: DueThisWeekIntent(), phrases: ["What's due in \(.applicationName)"],
                    shortTitle: "Due This Week", systemImageName: "flag")
        AppShortcut(intent: OverloadStatusIntent(), phrases: ["How's my average in \(.applicationName)"],
                    shortTitle: "Overload Status", systemImageName: "gauge.with.dots.needle.67percent")
    }
}
