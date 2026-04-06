//
//  AIKeyProvider.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 06/04/2026.
//

import Foundation
import os
import Security

/// Central resolver for the Anthropic API key and model configuration.
///
/// Key priority (first non-nil wins):
/// 1. User-provided key (BYOK) stored in the macOS Keychain via Settings
/// 2. Bundled key from `Secrets.plist` (XOR-obfuscated, gitignored)
/// 3. `DYNAMICMAC_API_KEY` environment variable (dev convenience)
///
/// The bundled key is XOR-obfuscated so it doesn't appear as plain text
/// in the .app bundle. This is *not* cryptographic security — a
/// determined attacker can still extract it — but it prevents casual
/// `strings` or hex-dump discovery.
///
/// Model configuration is read from `Secrets.plist` via the
/// `AnthropicModel` key, defaulting to `claude-sonnet-4-20250514`.
enum AIKeyProvider {

    // MARK: - API Key

    /// Returns the API key if available, or `nil` when unconfigured.
    static func apiKey() -> String? {
        // 1. User-provided key (BYOK) from Keychain.
        if let byok = readFromKeychain(), !byok.isEmpty {
            return byok
        }

        // 2. Bundled Secrets.plist (XOR-obfuscated, build-time embedded).
        if let key = readFromSecretsPlist() {
            return key
        }

        // 3. Environment variable fallback (development convenience).
        if let envKey = ProcessInfo.processInfo.environment["DYNAMICMAC_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }

        return nil
    }

    /// Whether the user has set their own API key via Settings.
    static var hasUserKey: Bool {
        guard let key = readFromKeychain() else { return false }
        return !key.isEmpty
    }

    // MARK: - BYOK (Keychain)

    private static let keychainService = "com.dynamicmac.api-key"
    private static let keychainAccount = "anthropic"

    /// Save a user-provided API key to the macOS Keychain.
    static func saveUserKey(_ key: String) {
        let data = Data(key.utf8)

        // Delete any existing item first.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !key.isEmpty else { return } // Empty = remove

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            DMLog.ai.error("Keychain save failed: \(status)")
        }
    }

    /// Remove the user-provided API key from the Keychain.
    static func removeUserKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Model

    private static let defaultModel = "claude-sonnet-4-20250514"

    /// The AI model identifier from `Secrets.plist`, falling back to a
    /// sensible default.
    static var model: String {
        guard let dict = secretsPlistDictionary(),
              let model = dict["AnthropicModel"] as? String,
              !model.isEmpty,
              model != "model-identifier-here" else {
            return defaultModel
        }
        return model
    }

    // MARK: - Bundled key (XOR-obfuscated)

    /// Static XOR key used to obfuscate the API key in Secrets.plist.
    /// Not a secret — the purpose is to prevent casual `strings` discovery,
    /// not to resist a determined reverse engineer.
    private static let xorKey: [UInt8] = [
        0xD7, 0x4A, 0xF1, 0x8C, 0x23, 0xB5, 0x6E, 0x99,
        0x0F, 0xE2, 0x57, 0xAB, 0x3D, 0xC8, 0x74, 0x16,
    ]

    private static func readFromSecretsPlist() -> String? {
        guard let dict = secretsPlistDictionary() else { return nil }

        // Try the obfuscated key first (base64-encoded XOR'd bytes).
        if let obfuscated = dict["AnthropicAPIKeyObfuscated"] as? String,
           !obfuscated.isEmpty,
           let decoded = deobfuscate(obfuscated) {
            return decoded
        }

        // Fall back to plain-text key for development convenience.
        if let key = dict["AnthropicAPIKey"] as? String,
           !key.isEmpty,
           key != "your-api-key-here" {
            return key
        }

        return nil
    }

    private static func secretsPlistDictionary() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else {
            return nil
        }
        return dict
    }

    // MARK: - XOR obfuscation

    /// XOR a byte array against the repeating `xorKey`.
    private static func xorBytes(_ input: [UInt8]) -> [UInt8] {
        input.enumerated().map { i, byte in
            byte ^ xorKey[i % xorKey.count]
        }
    }

    /// Decode a base64-encoded, XOR-obfuscated string back to plaintext.
    private static func deobfuscate(_ base64String: String) -> String? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        let decrypted = xorBytes([UInt8](data))
        guard let result = String(bytes: decrypted, encoding: .utf8),
              !result.isEmpty else {
            return nil
        }
        return result
    }

    /// Obfuscate a plain-text API key into a base64-encoded XOR'd string.
    /// Used by the build-time helper to generate the value for Secrets.plist.
    static func obfuscate(_ plainText: String) -> String {
        let encrypted = xorBytes([UInt8](plainText.utf8))
        return Data(encrypted).base64EncodedString()
    }
}
