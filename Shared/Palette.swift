//
//  Palette.swift
//  WatDash
//

import SwiftUI

/// Course colours, shared by the app and the widgets so MATH 137 is the same
/// blue everywhere. Indexed rather than stored as colours so the data file
/// stays small and a palette tweak recolours everything consistently.
enum Palette {
    static let courses: [(Double, Double, Double)] = [
        (0.26, 0.47, 0.96),  // blue
        (0.86, 0.24, 0.56),  // magenta
        (0.16, 0.66, 0.52),  // teal
        (0.95, 0.55, 0.12),  // orange
        (0.55, 0.36, 0.93),  // violet
        (0.85, 0.30, 0.25),  // red
        (0.20, 0.62, 0.86),  // sky
        (0.55, 0.62, 0.18),  // olive
        (0.62, 0.45, 0.30),  // brown
        (0.45, 0.48, 0.55),  // slate
    ]

    static func color(_ index: Int) -> Color {
        let rgb = courses[((index % courses.count) + courses.count) % courses.count]
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// University of Waterloo gold (same as WatAlarm).
    static let accent = Color(red: 0.98, green: 0.66, blue: 0.13)
    static let accentDeep = Color(red: 0.85, green: 0.50, blue: 0.05)
    static let good = Color(red: 0.20, green: 0.66, blue: 0.36)
    static let warn = Color(red: 0.95, green: 0.55, blue: 0.12)
    static let bad = Color(red: 0.86, green: 0.26, blue: 0.24)

    /// Colour for "how far above/below the target" readouts.
    static func margin(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 1.5 { return good }
        if value >= 0 { return warn }
        return bad
    }
}
