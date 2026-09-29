//
//  StringConvenience.swift
//  WatDash
//

import Foundation

extension String {
    /// Treats an empty string as absent (calendar exports are full of
    /// present-but-empty fields).
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Capture groups of the first match of `pattern`, or nil. Index 0 is the
    /// whole match; unmatched optional groups come back as "".
    ///
    /// NSRegularExpression rather than bare-slash literals, for the same reason
    /// as WatAlarm: the file compiles identically in Swift 5 and 6 modes.
    func firstMatch(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }

    /// Every match's capture groups.
    func allMatches(_ pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }

    /// Range (as NSRange) of the first match, for callers that strip tokens.
    func firstMatchRange(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        return regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length))?.range
    }

    func replacingMatches(_ pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        let ns = self as NSString
        return regex.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    /// Collapses runs of whitespace to single spaces.
    var collapsingWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
