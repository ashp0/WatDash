//
//  GradesView.swift
//  WatDash
//

import SwiftUI

/// Term view of the grade engine: where the cumulative average is heading,
/// how sure that is, and what it takes to stay above the overload line.
struct GradesView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var scenario: Double = 80
    @State private var scenarioOn = false

    var body: some View {
        let term = store.term
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary(term)
                scenarioCard(term)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Courses").font(.title3.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                        ForEach(store.courses) { course in
                            CourseGradeCard(course: course)
                        }
                    }
                }
                leverage(term)
                Text("Rule: Math students with a cumulative average of at least 80% may take six courses (CS advising FAQ). Below 80% you can petition the Standings and Petitions Committee. Course grades are rounded to whole numbers the way they appear on the transcript; CR/NCR courses don't count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("CS advising FAQ", destination: URL(string: "https://cs.uwaterloo.ca/current-undergraduate-students/frequently-asked-questions")!)
                    .font(.caption)
            }
            .padding(24)
        }
        .navigationTitle("Grades")
    }

    private func summary(_ term: GradeEngine.TermResult) -> some View {
        Card(padding: 20) {
            HStack(alignment: .center, spacing: 28) {
                MarginRing(value: term.projected, target: term.target, lineWidth: 12)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projected term average").font(.headline)
                    if let margin = term.margin {
                        Text("\(margin.signedOneDecimal) against your \(Int(term.target))% target")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.margin(margin))
                    } else {
                        Text("Needs grading schemes and a few marks").font(.title3).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        metric("Banked", term.floor.map { $0.oneDecimal } ?? "—", "if you scored 0 on everything left")
                        metric("Ceiling", term.ceiling.map { $0.oneDecimal } ?? "—", "if you scored 100 on everything left")
                        metric("Likely", term.low.flatMap { low in term.high.map { "\(low.oneDecimal)–\($0.oneDecimal)" } } ?? "—", "90% range")
                        metric("Chance ≥ \(Int(term.target))", term.probabilityAtLeastTarget.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "rough")
                    }
                    Label(SnapshotWriter.requirementText(term.requiredOnRemaining) + " (a uniform score on every remaining item)", systemImage: "target")
                        .font(.callout)
                    if let cumulative = term.cumulativeProjected, store.settings.previousUnits > 0 {
                        Text("Cumulative with earlier terms: \(cumulative.oneDecimal)").font(.callout)
                    }
                    if store.effectiveExamGap != store.settings.examGap {
                        Text("Exams projected \(store.effectiveExamGap.oneDecimal) points below coursework, learned from your marks.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Exams projected \(store.settings.examGap.oneDecimal) points below coursework until your own exam marks say otherwise.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit())
        }
        .help(help)
    }

    /// "What if I average X on everything left?" — computed on the fly, not saved.
    private func scenarioCard(_ term: GradeEngine.TermResult) -> some View {
        let inputs = store.gradeInputs.map { course -> GradeEngine.CourseInput in
            var course = course
            for c in course.components.indices {
                for i in course.components[c].items.indices where course.components[c].items[i].percent == nil {
                    course.components[c].items[i].whatIf = scenario
                }
            }
            return course
        }
        var parameters = store.gradeParameters
        parameters.examGap = 0
        let result = scenarioOn ? GradeEngine.evaluateTerm(inputs, parameters: parameters) : nil
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(isOn: $scenarioOn) { Text("What if I average").font(.headline) }
                        .toggleStyle(.switch)
                    Text("\(Int(scenario))%").font(.headline.monospacedDigit()).frame(width: 48)
                    Text("on everything left?").font(.headline)
                    Spacer()
                    if let projected = result?.projected {
                        Text("Term average → \(projected.oneDecimal)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.margin(projected - term.target))
                    }
                }
                Slider(value: $scenario, in: 40...100, step: 1)
                    .disabled(!scenarioOn)
                Text("Per-item what-ifs live on each course's Grades tab.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func leverage(_ term: GradeEngine.TermResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where marks move your average most").font(.title3.weight(.semibold))
            Card(padding: 8) {
                VStack(spacing: 0) {
                    let items = term.leverage.filter { ($0.due ?? .distantFuture) > store.now }.prefix(10)
                    if items.isEmpty {
                        Text("Nothing ungraded yet.").foregroundStyle(.secondary).padding(8)
                    }
                    ForEach(Array(items)) { item in
                        HStack {
                            CourseChip(code: item.code)
                            Text(item.title).font(.callout.weight(.medium))
                            Spacer()
                            Text(item.due.map { $0.dayMonth } ?? "TBA").font(.caption).foregroundStyle(.secondary)
                            Text("\(item.courseWeight.oneDecimal)% of course").font(.caption).frame(width: 110, alignment: .trailing)
                            Text("+\(String(format: "%.2f", item.termImpact * 10)) avg / 10 marks")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.accentDeep)
                                .frame(width: 150, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
}

struct CourseGradeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        let result = store.courseResult(course.code)
        let color = Palette.color(course.colorIndex)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CourseChip(code: course.code)
                    Text(course.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !course.countsTowardAverage {
                        Text("not counted").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let result, result.requirement != .noScheme {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading) {
                            Text(result.current.map { $0.oneDecimal } ?? "—")
                                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("current").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(result.projected.map { $0.oneDecimal } ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
                            Text("projected").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(Int((result.gradedFraction * 100).rounded()))%").font(.title3.weight(.semibold)).monospacedDigit()
                            Text("marked").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GradeBar(floor: result.floor, ceiling: result.ceiling, projected: result.projected,
                             low: result.projectedLow, high: result.projectedHigh, target: store.settings.targetAverage, color: color)
                    Text(requirementLine(result.requirement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warning = result.weightWarning {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.warn)
                    }
                } else {
                    Text("No grading scheme yet.").foregroundStyle(.secondary)
                }
                Button("Open grades") { router.selection = .course(course.id) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func requirementLine(_ requirement: GradeEngine.Requirement) -> String {
        switch requirement {
        case .secured: "Already above \(Int(store.settings.targetAverage)) whatever happens."
        case .unreachable: "\(Int(store.settings.targetAverage)) is out of reach in this course; other courses must carry it."
        case let .needs(value): "Needs \(value.oneDecimal)% on everything left to finish at \(Int(store.settings.targetAverage))."
        case .noRemainingWork: "All marks are in."
        case .noScheme: "Add a grading scheme."
        }
    }
}
