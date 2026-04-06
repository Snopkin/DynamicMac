#!/usr/bin/env swift

// obfuscate_api_key.swift
// Generates the XOR-obfuscated base64 value for Secrets.plist.
//
// Usage:
//   swift Scripts/obfuscate_api_key.swift sk-ant-api03-YOUR-KEY-HERE
//
// Then paste the output into Secrets.plist under AnthropicAPIKeyObfuscated.

import Foundation

let xorKey: [UInt8] = [
    0xD7, 0x4A, 0xF1, 0x8C, 0x23, 0xB5, 0x6E, 0x99,
    0x0F, 0xE2, 0x57, 0xAB, 0x3D, 0xC8, 0x74, 0x16,
]

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift \(CommandLine.arguments[0]) <api-key>\n", stderr)
    exit(1)
}

let apiKey = CommandLine.arguments[1]
let inputBytes = [UInt8](apiKey.utf8)
let encrypted = inputBytes.enumerated().map { i, byte in
    byte ^ xorKey[i % xorKey.count]
}
let base64 = Data(encrypted).base64EncodedString()

print(base64)
print("")
print("Paste the above value into Secrets.plist as AnthropicAPIKeyObfuscated.")
print("You can then clear the plain-text AnthropicAPIKey field.")
