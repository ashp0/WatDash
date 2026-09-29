//
//  SmartCapture.swift
//  WatDash
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional language layer in front of `QuickCaptureParser`.
///
/// The on-device model (Apple Intelligence, private and free) is good at
/// reading a messy sentence — "hey the 135 midterm got moved to the 23rd,
/// same time" — and bad at date arithmetic. So it only *normalizes* the text
/// into the short form the deterministic parser already understands; the
/// parser still computes every date. When the model is unavailable (Apple
/// Intelligence off, unsupported Mac), capture silently falls back to the
/// parser alone.
enum SmartCapture {

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static var availabilityNote: String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return "On-device model ready."
        case .unavailable: return "Apple Intelligence isn't available, so capture uses the built-in parser only."
        @unknown default: return "On-device model status unknown."
        }
        #else
        return "This build has no on-device model support."
        #endif
    }

    #if canImport(FoundationModels)
    @Generable
    struct Normalized {
        @Guide(description: "Course code like 'CS 135' or 'MATH 137', or empty if none is mentioned.")
        var courseCode: String
        @Guide(description: "One of: lecture, tutorial, lab, quiz, midterm, exam, assignment, deadline, office hours, event.")
        var kind: String
        @Guide(description: "Short title without the course code, date or time, e.g. 'Assignment 4' or 'Hack the North info session'.")
        var title: String
        @Guide(description: "The day exactly as written, e.g. 'tue', 'tomorrow', 'oct 23'. Empty if none.")
        var day: String
        @Guide(description: "The time or time range exactly as written, e.g. '2-3pm' or '11:59pm'. Empty if none.")
        var time: String
        @Guide(description: "Building and room like 'MC 4065', or a place name. Empty if none.")
        var location: String
        @Guide(description: "True if it repeats every week.")
        var weekly: Bool
        @Guide(description: "End of repetition exactly as written, e.g. 'dec 4'. Empty if none.")
        var until: String
    }
    #endif

    /// Returns a parse that is at least as good as the plain parser's.
    static func parse(_ text: String, now: Date, knownCourses: [String]) async -> CaptureResult {
        let plain = QuickCaptureParser.parse(text, now: now, knownCourses: knownCourses)
        #if canImport(FoundationModels)
        guard isAvailable, plain.confidence < 0.9 else { return plain }
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: "You extract calendar fields from a university student's note. Copy dates and times exactly as written; never compute or invent them."
            )
            let response = try await session.respond(to: text, generating: Normalized.self)
            let fields = response.content
            let kindWord: String
            switch fields.kind.lowercased() {
            case "midterm": kindWord = "midterm"
            case "exam": kindWord = "final exam"
            case "office hours": kindWord = "OH"
            case "event", "": kindWord = ""
            default: kindWord = fields.kind
            }
            let rebuilt = [fields.courseCode, kindWord, fields.title, fields.day, fields.time,
                           fields.location.isEmpty ? "" : "@ \(fields.location)",
                           fields.weekly ? "weekly" : "", fields.until.isEmpty ? "" : "until \(fields.until)"]
                .filter { !$0.trimmed.isEmpty }
                .joined(separator: " ")
            let smart = QuickCaptureParser.parse(rebuilt, now: now, knownCourses: knownCourses)
            return smart.confidence >= plain.confidence ? smart : plain
        } catch {
            Log.importer.info("Smart capture fell back: \(error.localizedDescription, privacy: .public)")
            return plain
        }
        #else
        return plain
        #endif
    }
}
