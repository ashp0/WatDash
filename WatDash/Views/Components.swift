//
//  Components.swift
//  WatDash
//

import SwiftUI

/// Standard card container used across the app (WatAlarm's card, adapted
/// for macOS window sizes).
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

struct CardHeader: View {
    var title: String
    var symbol: String
    var trailing: String?
    var tint: Color = Palette.accentDeep

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Coloured course code capsule: the one visual that ties a row to its course.
struct CourseChip: View {
    @Environment(AppStore.self) private var store
    var code: String?
    var compact = false

    var body: some View {
        if let code {
            let color = store.color(for: code)
            Text(compact ? code.replacingOccurrences(of: " ", with: "") : code)
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
                .fixedSize()
        }
    }
}

struct CourseDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Symbol + kind colour for a timetable entry.
struct KindIcon: View {
    var kind: EventKind
    var color: Color

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Opens Odyssey's assessment schedule, where every in-person quiz, midterm and
/// final shows its room and assigned seat. `compact` is the short form for rows.
struct SeatingButton: View {
    var compact = false

    var body: some View {
        Link(destination: Waterloo.seatingURL) {
            Label(compact ? "Seat" : "Seat on Odyssey", systemImage: "chair")
        }
        .help("Room, seat and time on Odyssey")
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// One line of an agenda: time, kind icon, title, course chip, location.
struct AgendaRow: View {
    @Environment(AppStore.self) private var store
    var item: AgendaItem
    var showDate = false
    var showCountdown = false

    var body: some View {
        let color = store.color(for: item.courseCode)
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if showDate {
                    Text(item.start.relativeDayLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(item.isAllDay ? "All day" : item.start.shortTime)
                    .font(showDate ? .caption2 : .caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: showDate ? 78 : 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let code = item.courseCode, !item.title.contains(code) {
                        CourseChip(code: code, compact: true)
                    }
                    Text(secondaryLine)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if showCountdown, item.start > store.now {
                Text(item.start.compactCountdown(from: store.now))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.start.timeIntervalSince(store.now) < 86_400 ? Palette.warn : .secondary)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var secondaryLine: String {
        var parts = [item.kind.label]
        if let location = item.location { parts.append(location) }
        if let detail = item.detail, item.kind.isAssessment { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}

/// Horizontal bar with a floor, projection band and target tick.
struct GradeBar: View {
    var floor: Double
    var ceiling: Double
    var projected: Double?
    var low: Double?
    var high: Double?
    var target: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x: (Double) -> CGFloat = { value in CGFloat(min(100, max(0, value)) / 100) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                // Reachable range: floor → ceiling.
                Capsule().fill(color.opacity(0.18))
                    .frame(width: max(0, x(ceiling) - x(floor)))
                    .offset(x: x(floor))
                // Banked.
                Capsule().fill(color.opacity(0.55)).frame(width: x(floor))
                if let low, let high {
                    Capsule().fill(color.opacity(0.35))
                        .frame(width: max(2, x(high) - x(low)))
                        .offset(x: x(low))
                }
                if let projected {
                    Circle().fill(color)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .offset(x: x(projected) - 5)
                }
                Rectangle().fill(.primary.opacity(0.7))
                    .frame(width: 1.5, height: proxy.size.height + 6)
                    .offset(x: x(target) - 0.75)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Projected \(projected.map { String(format: "%.1f", $0) } ?? "unknown") against a target of \(Int(target))")
    }
}

/// Circular gauge used by the overload tracker.
struct MarginRing: View {
    var value: Double?
    var target: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        let fraction = min(1, max(0, (value ?? 0) / 100))
        let color = Palette.margin(value.map { $0 - target })
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2
            ZStack {
                Circle().stroke(.quaternary, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Target tick, straddling the ring at the target's angle.
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: 2.5, height: lineWidth + 8)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(target / 100 * 360))
                VStack(spacing: 0) {
                    Text(value.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: side * 0.23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("projected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension Double {
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
    var noDecimals: String { formatted(.number.precision(.fractionLength(0))) }
    var signedOneDecimal: String { (self >= 0 ? "+" : "−") + abs(self).oneDecimal }
}

extension View {
    /// Section title used above grouped content in the detail panes.
    func sectionTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            self
        }
    }
}
