//
//  DeterministicID.swift
//  WatDash (from WatAlarm)
//

import CryptoKit
import Foundation

/// Builds stable identifiers from strings.
///
/// Same trick as WatAlarm: everything WatDash writes to the outside world
/// (Apple Calendar events, notifications) gets an identifier derived from what
/// it *is* — course, kind, start time — rather than a random one. Re-running a
/// sync with unchanged data then produces the same ids, so reconciliation is a
/// set difference instead of a delete-and-recreate churn, and a duplicate is
/// impossible by construction.
enum DeterministicID {
    static func uuid(from string: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data(string.utf8)).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80  // RFC 4122 variant
        let bytes = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: bytes)
    }

    /// Short, stable hex hash, safe for notification identifiers and URLs.
    static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
