//
//  Keychain.swift
//  WatDash
//

import Foundation
import Security

/// API keys live in the login keychain, never in the JSON store, so a copied or
/// synced data file can't leak them.
enum Keychain {
    private static let service = "com.ashwinpaudel.WatDash"

    enum Key: String {
        case openData = "uw-open-data-api-key"
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.nilIfEmpty
    }

    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value?.trimmed, !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
