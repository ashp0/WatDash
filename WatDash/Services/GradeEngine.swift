//
//  GradeEngine.swift
//  WatDash
//

import Foundation

/// Turns grading schemes and scores into the numbers that matter for the
/// overload rule: what's banked, where you're heading, and what you need.
///
/// Waterloo's rule (per the CS advising FAQ): Math students with a *cumulative
/// average* of at least 80% can take six courses. That's a unit-weighted mean
/// of whole-number course grades, not a GPA — so the engine works in
/// percentages, weights courses by units, and can round course grades the way
/// the transcript does.
///
/// Pure and deterministic: every input is passed in, so Tests/Checks.swift can
/// pin the arithmetic (drops, replacement rules, the exam-pass cap) exactly.
enum GradeEngine {

    // MARK: - Inputs

    struct ItemInput: Sendable {
        var id: UUID
        var title: String
        var due: Date?
        var percent: Double?     // graded score
        var whatIf: Double?      // hypothetical, projections only
        var excused: Bool = false
    }

    struct ComponentInput: Sendable {
        var id: UUID
        var name: String
        var weight: Double
        var dropLowest: Int
        var expectedCount: Int?
        var isExam: Bool
        var items: [ItemInput]
    }

    struct CourseInput: Sendable {
        var code: String
        var units: Double
        var components: [ComponentInput]
        var rules: [GradeRule]
    }

    struct Parameters: Sendable {
        var target: Double = 80
        var examGap: Double = 8
        var examSigma: Double = 10
        var courseworkSigma: Double = 6
        var roundCourseGrades: Bool = true
    }

    // MARK: - Outputs

    enum Requirement: Equatable, Sendable {
        case secured          // even zeros on everything left clears the target
        case unreachable      // even 100s on everything left fall short
        case needs(Double)    // uniform score needed on everything left
        case noRemainingWork
        case noScheme
    }

    struct CourseResult: Sendable {
        var code: String
        var units: Double
        var current: Double?     // average on graded work so far
        var floor: Double        // zeros on everything left
        var ceiling: Double      // 100s on everything left
        var projected: Double?   // calibrated guess, with what-ifs applied
        var sigma: Double        // rough uncertainty of `projected`
        var gradedFraction: Double  // share of the course already marked
        var requirement: Requirement
        var weightWarning: String?

        var projectedLow: Double? { projected.map { max(floor, $0 - 1.645 * sigma) } }
        var projectedHigh: Double? { projected.map { min(ceiling, $0 + 1.645 * sigma) } }
    }

    struct LeverageItem: Identifiable, Sendable {
        var id: UUID
        var code: String
        var title: String
        var due: Date?
        /// Share of the course grade this item carries (0–100).
        var courseWeight: Double
        /// Points of term average per point scored on this item.
        var termImpact: Double
    }

    struct TermResult: Sendable {
        var courses: [CourseResult]
        var units: Double
        var projected: Double?
        var floor: Double?
        var ceiling: Double?
        var sigma: Double
        var probabilityAtLeastTarget: Double?
        var requiredOnRemaining: Requirement
        var cumulativeProjected: Double?
        var leverage: [LeverageItem]
        var target: Double

        var margin: Double? { projected.map { $0 - target } }
        var low: Double? { projected.map { $0 - 1.645 * sigma } }
        var high: Double? { projected.map { $0 + 1.645 * sigma } }
    }

    // MARK: - Course

    /// How ungraded work is filled in for one evaluation.
    private enum Fill {
        case zeros, hundreds, uniform(Double), projection(course: Double?, gap: Double)
    }

    static func evaluate(_ course: CourseInput, parameters: Parameters) -> CourseResult {
        let totalWeight = course.components.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return CourseResult(code: course.code, units: course.units, current: nil, floor: 0, ceiling: 100,
                                projected: nil, sigma: 0, gradedFraction: 0, requirement: .noScheme, weightWarning: nil)
        }

        let current = currentAverage(course)
        let floor = grade(course, fill: .zeros)
        let ceiling = grade(course, fill: .hundreds)
        // No marks yet means no projection: guessing a number before any
        // evidence is exactly the false precision this screen exists to avoid.
        let projected = current == nil
            ? nil
            : grade(course, fill: .projection(course: current, gap: parameters.examGap))

        // Uncertainty: each unknown slot contributes its share of the grade
        // times a per-kind spread. Crude, but honest about exams being wide.
        var variance = 0.0
        var gradedWeight = 0.0
        for component in course.components {
            let slots = slotCount(component)
            guard slots > 0 else { continue }
            let kept = max(1, slots - component.dropLowest)
            let share = component.weight / totalWeight / Double(kept)
            let known = component.items.filter { !$0.excused && ($0.percent != nil) }.count
            gradedWeight += component.weight / totalWeight * min(1, Double(known) / Double(kept))
            let unknownSlots = max(0, min(kept, slots - known) - component.items.filter { !$0.excused && $0.percent == nil && $0.whatIf != nil }.count)
            let sigma = component.isExam ? parameters.examSigma : parameters.courseworkSigma
            variance += Double(unknownSlots) * pow(share * sigma, 2)
        }

        let requirement: Requirement
        if floor >= parameters.target {
            requirement = .secured
        } else if abs(ceiling - floor) < 0.0001 {
            requirement = .noRemainingWork
        } else if ceiling < parameters.target {
            requirement = .unreachable
        } else {
            requirement = .needs(solve { grade(course, fill: .uniform($0)) >= parameters.target })
        }

        let warning = abs(totalWeight - 100) > 0.01
            ? "Weights add up to \(totalWeight.formatted(.number.precision(.fractionLength(0...1))))%, not 100%. Grades are scaled to fit."
            : nil

        return CourseResult(code: course.code, units: course.units, current: current, floor: floor, ceiling: ceiling,
                            projected: projected, sigma: sqrt(variance), gradedFraction: gradedWeight,
                            requirement: requirement, weightWarning: warning)
    }

    /// Average on marked work only, ignoring components with nothing marked.
    static func currentAverage(_ course: CourseInput) -> Double? {
        var weighted = 0.0
        var weights = 0.0
        for component in course.components {
            let graded = component.items.filter { !$0.excused }.compactMap(\.percent)
            guard !graded.isEmpty else { continue }
            let kept = max(1, slotCount(component) - component.dropLowest)
            // Only drop once there are more marks than kept slots — the dropped
            // quiz will be the worst of all ten, not necessarily of these two.
            let values = graded.count > kept ? Array(graded.sorted(by: >).prefix(kept)) : graded
            weighted += component.weight * mean(values)
            weights += component.weight
        }
        return weights > 0 ? weighted / weights : nil
    }

    private static func slotCount(_ component: ComponentInput) -> Int {
        let active = component.items.filter { !$0.excused }.count
        let excused = component.items.count - active
        let expected = (component.expectedCount ?? component.items.count) - excused
        return max(active, expected, component.items.isEmpty ? 1 : 0)
    }

    private static func grade(_ course: CourseInput, fill: Fill) -> Double {
        let totalWeight = course.components.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }

        // Component averages under this fill.
        var averages: [UUID: Double] = [:]
        for component in course.components {
            let slots = slotCount(component)
            var values: [Double] = []
            let active = component.items.filter { !$0.excused }
            let componentCurrent: Double? = {
                let graded = active.compactMap(\.percent)
                return graded.isEmpty ? nil : mean(graded)
            }()

            func filled(_ item: ItemInput?) -> Double {
                if let percent = item?.percent { return percent }
                switch fill {
                case .zeros: return 0
                case .hundreds: return 100
                case let .uniform(value): return value
                case let .projection(courseAverage, gap):
                    if let whatIf = item?.whatIf { return whatIf }
                    if let componentCurrent { return componentCurrent }
                    guard let courseAverage else { return 0 }
                    return component.isExam ? max(0, courseAverage - gap) : courseAverage
                }
            }

            values = active.map { filled($0) }
            if values.count < slots {
                values += Array(repeating: filled(nil), count: slots - values.count)
            }
            let kept = max(1, slots - component.dropLowest)
            let best = values.sorted(by: >).prefix(kept)
            averages[component.id] = best.isEmpty ? 0 : best.reduce(0, +) / Double(kept)
        }

        for rule in course.rules {
            if case let .replaceIfBetter(target, with) = rule,
               let targetAverage = averages[target], let withAverage = averages[with] {
                averages[target] = max(targetAverage, withAverage)
            }
        }

        var total = 0.0
        for component in course.components {
            total += component.weight * (averages[component.id] ?? 0)
        }
        var result = total / totalWeight

        for rule in course.rules {
            if case let .mustPass(ids, threshold) = rule {
                let parts = course.components.filter { ids.contains($0.id) }
                let weight = parts.reduce(0) { $0 + $1.weight }
                guard weight > 0 else { continue }
                let examAverage = parts.reduce(0) { $0 + $1.weight * (averages[$1.id] ?? 0) } / weight
                if examAverage < threshold { result = min(result, examAverage) }
            }
        }
        return min(100, max(0, result))
    }

    // MARK: - Term

    static func evaluateTerm(
        _ courses: [CourseInput],
        parameters: Parameters,
        previousUnits: Double = 0,
        previousAverage: Double? = nil
    ) -> TermResult {
        let results = courses.map { evaluate($0, parameters: parameters) }
        let counted = results.filter { $0.requirement != .noScheme }
        let units = counted.reduce(0) { $0 + $1.units }

        func rounded(_ value: Double) -> Double {
            parameters.roundCourseGrades ? value.rounded() : value
        }

        var projected: Double?
        var floor: Double?
        var ceiling: Double?
        var sigma = 0.0
        if units > 0 {
            let withProjection = counted.filter { $0.projected != nil }
            let projectedUnits = withProjection.reduce(0) { $0 + $1.units }
            if projectedUnits > 0 {
                projected = withProjection.reduce(0) { $0 + rounded($1.projected!) * $1.units } / projectedUnits
                sigma = sqrt(withProjection.reduce(0) { $0 + pow($1.units / projectedUnits * $1.sigma, 2) })
            }
            floor = counted.reduce(0) { $0 + $1.floor * $1.units } / units
            ceiling = counted.reduce(0) { $0 + $1.ceiling * $1.units } / units
        }

        let probability: Double? = projected.map { value in
            guard sigma > 0.01 else { return value >= parameters.target ? 1 : 0 }
            // Continuity: the transcript rounds, so 79.5 counts as 80.
            let threshold = parameters.roundCourseGrades ? parameters.target - 0.5 : parameters.target
            return normalCDF((value - threshold) / sigma)
        }

        // Uniform score needed on everything left, across all courses.
        let scheduled = courses.filter { $0.components.reduce(0) { $0 + $1.weight } > 0 }
        let requirement: Requirement
        if units == 0 {
            requirement = .noScheme
        } else if let floor, floor >= parameters.target {
            requirement = .secured
        } else if let ceiling, let floor, abs(ceiling - floor) < 0.0001 {
            requirement = .noRemainingWork
        } else if let ceiling, ceiling < parameters.target {
            requirement = .unreachable
        } else {
            requirement = .needs(solve { x in
                let total = scheduled.reduce(0.0) { sum, course in
                    sum + grade(course, fill: .uniform(x)) * course.units
                }
                return total / units >= parameters.target
            })
        }

        var cumulative: Double?
        if let projected {
            if let previousAverage, previousUnits > 0 {
                cumulative = (previousAverage * previousUnits + projected * units) / (previousUnits + units)
            } else {
                cumulative = projected
            }
        }

        return TermResult(courses: results, units: units, projected: projected, floor: floor, ceiling: ceiling,
                          sigma: sigma, probabilityAtLeastTarget: probability, requiredOnRemaining: requirement,
                          cumulativeProjected: cumulative, leverage: leverage(courses, totalUnits: units), target: parameters.target)
    }

    /// Ungraded items ranked by how much a point on them moves the average.
    static func leverage(_ courses: [CourseInput], totalUnits: Double) -> [LeverageItem] {
        guard totalUnits > 0 else { return [] }
        var items: [LeverageItem] = []
        for course in courses {
            let totalWeight = course.components.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { continue }
            for component in course.components {
                let kept = max(1, slotCount(component) - component.dropLowest)
                let courseWeight = component.weight / totalWeight * 100 / Double(kept)
                for item in component.items where item.percent == nil && !item.excused {
                    items.append(LeverageItem(
                        id: item.id, code: course.code, title: item.title, due: item.due,
                        courseWeight: courseWeight,
                        termImpact: courseWeight / 100 * course.units / totalUnits
                    ))
                }
            }
        }
        return items.sorted { $0.termImpact > $1.termImpact }
    }

    /// Learned exam gap: how much lower exams come out than coursework, across
    /// courses that have both. Nil until there's evidence.
    static func learnedExamGap(_ courses: [CourseInput]) -> Double? {
        var gaps: [Double] = []
        for course in courses {
            let exams = course.components.filter(\.isExam).flatMap(\.items).compactMap(\.percent)
            let work = course.components.filter { !$0.isExam }.flatMap(\.items).compactMap(\.percent)
            guard !exams.isEmpty, !work.isEmpty else { continue }
            gaps.append(mean(work) - mean(exams))
        }
        return gaps.isEmpty ? nil : mean(gaps)
    }

    // MARK: - Math

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Smallest x in [0, 100] for which `predicate(x)` holds (monotone).
    private static func solve(_ predicate: (Double) -> Bool) -> Double {
        var low = 0.0
        var high = 100.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if predicate(mid) { high = mid } else { low = mid }
        }
        return high
    }

    static func normalCDF(_ z: Double) -> Double {
        0.5 * erfc(-z / 2.0.squareRoot())
    }
}

// MARK: - Store adapters

extension GradeEngine {
    /// Builds engine input from the store's models.
    static func input(for course: Course, assessments: [Assessment]) -> CourseInput {
        let mine = assessments.filter { $0.courseCode == course.code }
        let components = course.scheme.components.map { component in
            ComponentInput(
                id: component.id,
                name: component.name,
                weight: component.weight,
                dropLowest: component.dropLowest,
                expectedCount: component.expectedCount,
                isExam: component.isExam,
                items: mine.filter { $0.componentID == component.id }
                    .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                    .map { ItemInput(id: $0.id, title: $0.title, due: $0.due, percent: $0.percent, whatIf: $0.whatIf, excused: $0.isExcused) }
            )
        }
        return CourseInput(code: course.code, units: course.units, components: components, rules: course.scheme.rules)
    }
}
