//
//  MediaRemoteAdapterBridge.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import Foundation

/// Drives `ungive/mediaremote-adapter` by spawning `/usr/bin/perl` against
/// the vendored script and framework, reading newline-delimited JSON
/// envelopes from stdout, and merging them into a running snapshot of
/// what is currently playing on the system.
///
/// The adapter is the only viable system-wide Now Playing path on macOS
/// 15.4 and later: Apple locked down `mediaremoted` to only serve
/// processes whose bundle ID starts with `com.apple.*`, and `/usr/bin/perl`
/// ships as `com.apple.perl5`, so routing through Perl is still allowed.
/// See TECHNICAL_PLAN.md for the long-form background.
///
/// Wire contract (envelope per line of stdout):
///
/// ```
/// { "type": "data", "diff": Bool, "payload": { ...keys... } }
/// ```
///
/// - When `diff: false`, `payload` is a full snapshot. An **empty**
///   payload in this mode means "nothing is currently playing".
/// - When `diff: true`, `payload` contains only the keys that changed
///   since the last emitted state. A JSON `null` on a key means "remove
///   this key". Keys not present mean "unchanged".
@MainActor
final class MediaRemoteAdapterBridge: MediaSource {

    var onUpdate: ((NowPlayingInfo?) -> Void)?

    private let perlPath = "/usr/bin/perl"
    private let scriptURL: URL
    private let frameworkURL: URL

    private var streamProcess: Process?
    private var stdoutBuffer = Data()

    /// Running merged state. Mirrors whatever the adapter last told us
    /// about the now-playing session, so incoming diffs can be applied.
    private var currentPayload: [String: Any] = [:]

    init?() {
        // The Perl script ships as a plain Copy Bundle Resource, landing
        // at the top level of Contents/Resources (Xcode's file-system
        // sync group flattens subdirectories). The framework is embedded
        // via a dedicated Copy Files phase into Contents/Frameworks.
        guard
            let script = Bundle.main.url(
                forResource: "mediaremote-adapter",
                withExtension: "pl"
            ),
            let frameworksPath = Bundle.main.privateFrameworksPath
        else {
            return nil
        }
        let framework = URL(fileURLWithPath: frameworksPath)
            .appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else {
            return nil
        }
        self.scriptURL = script
        self.frameworkURL = framework
    }

    // MARK: - MediaSource

    func start() {
        guard streamProcess == nil else { return }
        spawnStream()
    }

    func stop() {
        streamProcess?.terminationHandler = nil
        streamProcess?.terminate()
        streamProcess = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
    }

    func send(_ command: MediaCommand) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [
            scriptURL.path,
            frameworkURL.path,
            "send",
            String(command.rawValue)
        ]
        // We do not wait for the short-lived `send` subprocess; it exits
        // on its own after issuing the command. Swallow stdout/stderr so
        // it doesn't inherit ours.
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }

    // MARK: - Stream subprocess

    private func spawnStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [
            scriptURL.path,
            frameworkURL.path,
            "stream"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // stdout — JSONL envelopes.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingestStdout(data)
            }
        }

        // stderr — drain to avoid full-pipe blocking. Non-fatal per the
        // adapter's documented contract (only the exit code matters).
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleStreamTermination()
            }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            streamProcess = nil
        }
    }

    private func handleStreamTermination() {
        streamProcess = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        currentPayload.removeAll()
        onUpdate?(nil)

        // Auto-restart with a short backoff so a broken mediaremoted or a
        // macOS update that breaks the adapter does not spin-loop fork.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.spawnStream()
        }
    }

    // MARK: - stdout framing and envelope decode

    private func ingestStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineRange = stdoutBuffer.startIndex..<newlineIndex
            let line = stdoutBuffer.subdata(in: lineRange)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineIndex)

            guard !line.isEmpty else { continue }
            handleEnvelopeLine(line)
        }
    }

    private func handleEnvelopeLine(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String,
            type == "data"
        else {
            return
        }

        let isDiff = (object["diff"] as? Bool) ?? false
        let payload = (object["payload"] as? [String: Any]) ?? [:]

        if isDiff {
            mergeDiff(payload)
        } else {
            currentPayload = payload
        }

        publishCurrentState()
    }

    /// Apply a diff payload on top of `currentPayload`. Keys present with
    /// a non-null value replace the previous value; keys present with
    /// `NSNull` are removed; keys not present are left untouched.
    private func mergeDiff(_ diff: [String: Any]) {
        for (key, value) in diff {
            if value is NSNull {
                currentPayload.removeValue(forKey: key)
            } else {
                currentPayload[key] = value
            }
        }
    }

    private func publishCurrentState() {
        let info = Self.makeInfo(from: currentPayload)
        onUpdate?(info)
    }

    /// Convert a merged adapter payload into a consumer-facing
    /// `NowPlayingInfo`. An empty payload (the adapter's "nothing is
    /// playing" signal) maps to `nil`.
    private static func makeInfo(from payload: [String: Any]) -> NowPlayingInfo? {
        guard !payload.isEmpty else { return nil }

        // Mandatory per adapter source (keys.m::mandatoryPayloadKeys):
        // processIdentifier, title, playing. Absence of `title` is the
        // cleanest proxy for "not really playing anything".
        guard payload["title"] is String else { return nil }

        return NowPlayingInfo(
            bundleIdentifier: payload["bundleIdentifier"] as? String,
            parentApplicationBundleIdentifier: payload["parentApplicationBundleIdentifier"] as? String,
            title: payload["title"] as? String,
            artist: payload["artist"] as? String,
            album: payload["album"] as? String,
            duration: payload["duration"] as? Double,
            elapsedTime: payload["elapsedTime"] as? Double,
            isPlaying: (payload["playing"] as? Bool) ?? false,
            artworkBase64: payload["artworkData"] as? String,
            artworkMimeType: payload["artworkMimeType"] as? String
        )
    }
}
