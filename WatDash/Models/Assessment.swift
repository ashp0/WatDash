//
//  Assessment.swift
//  WatDash
//

import Foundation

/// Something marked: a quiz, an assignment, a midterm. Lives in the canonical
/// store alongside events; its date puts it on the timetable and its component
/// puts it into the grade engine.
struct Assessment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var courseCode: String
    var title: String
    var kind: EventKind = .assignment
    var componentID: UUID?
    /// Start (or due time for assignments). Nil = TBA, e.g. finals before the
    /// Registrar posts the schedule.
    var due: Date?
    /// End of the writing window; equal to `due` for point-in-time deadlines.
    var end: Date?
    var coverage: String?
    var location: String?
    var score: Double?
    var outOf: Double = 100
    /// Hypothetical score (percent) used only by what-if projections.
    var whatIf: Double?
    /// Exemption (e.g. documented absence): weight shifts to the others.
    var isExcused: Bool = false
    var isDone: Bool = false
    /// Idempotency key for importers: "<course folder>:<row title>".
    var sourceKey: String?
    var sourceID: UUID?
    var notes: String?

    var percent: Double? {
        guard let score, outOf > 0 else { return nil }
        return score / outOf * 100
    }

    var isGraded: Bool { score != nil }

    var agendaEnd: Date? {
        guard let due else { return nil }
        if let end, end > due { return end }
        return kind.isDue ? due : due.addingTimeInterval(defaultDuration)
    }

    private var defaultDuration: TimeInterval {
        switch kind {
        case .quiz: 50 * 60
        case .test: 110 * 60
        case .exam: 150 * 60
        default: 0
        }
    }
}

enum GradeRule: Codable, Hashable, Sendable, Identifiable {
    /// "The final replaces the midterm if it's better."
    case replaceIfBetter(target: UUID, with: UUID)
    /// "You must pass the exam component to pass the course": if the weighted
    /// average of `components` is below `threshold`, the course grade is
    /// capped at that average.
    case mustPass(components: [UUID], threshold: Double)

    var id: String {
        switch self {
        case let .replaceIfBetter(target, with): "replace-\(target)-\(with)"
        case let .mustPass(components, threshold): "pass-\(components.map(\.uuidString).joined())-\(threshold)"
        }
    }
}

/// A grading scheme, straight from the outline: components with weights and
/// drop rules, plus conditional rules.
struct GradeScheme: Codable, Hashable, Sendable {
    var components: [GradeComponent] = []
    var rules: [GradeRule] = []

    var totalWeight: Double { components.reduce(0) { $0 + $1.weight } }

    func component(named name: String) -> GradeComponent? {
        let lower = name.lowercased()
        return components.first { $0.name.lowercased() == lower }
            ?? components.first { lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower) }
    }

    /// Best component for a new assessment of `kind` titled `title`.
    func guessComponent(kind: EventKind, title: String) -> GradeComponent? {
        let lower = title.lowercased()
        // A component named after the item wins ("Midterm 2" → "Midterm 2", not
        // the first component that mentions a midterm; "Skills challenge 1" →
        // "Skills challenges"), before any keyword guess.
        if let named = components.first(where: { $0.name.lowercased() == lower }) { return named }
        if let named = components.first(where: { component in
            var stem = component.name.lowercased()
            if stem.hasSuffix("s") { stem.removeLast() }
            return stem.count >= 4 && lower.hasPrefix(stem)
        }) { return named }
        let keywords: [String]
        switch kind {
        case .quiz: keywords = ["quiz"]
        case .test: keywords = ["midterm", "test"]
        case .exam: keywords = ["final", "exam"]
        case .assignment: keywords = ["assignment", "homework", "problem set", "lab", "project"]
        default: keywords = []
        }
        if lower.contains("final") { return components.first { $0.name.lowercased().contains("final") } }
        if lower.contains("midterm") { return components.first { $0.name.lowercased().contains("midterm") } }
        for keyword in keywords {
            if let match = components.first(where: { $0.name.lowercased().contains(keyword) }) { return match }
        }
        return nil
    }
}

struct GradeComponent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// Percent of the course grade.
    var weight: Double
    /// Lowest N dropped ("best 9 of 10" = drop 1).
    var dropLowest: Int = 0
    /// How many items the component will have by term end; lets the engine
    /// reason about quizzes that don't exist in the store yet.
    var expectedCount: Int?
    /// Exams are projected more conservatively than coursework.
    var isExam: Bool = false
}
