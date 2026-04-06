//
//  AboutSettingsTab.swift
//  DynamicMac
//
//  Created by Lidor Nir Shalom on 05/04/2026.
//

import AppKit
import SwiftUI

/// About tab: app name, version, copyright, and third-party attributions.
/// Version and build number are read from the bundle at runtime so the
/// displayed values track whatever Xcode's archive step produces.
struct AboutSettingsTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                acknowledgements
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "oval.fill")
                .font(.system(size: 44))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("DynamicMac")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Copyright © 2026 Lidor Nir Shalom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Acknowledgements

    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acknowledgements")
                .font(.headline)

            AcknowledgementRow(
                name: "DynamicNotchKit",
                license: "MIT License",
                url: URL(string: "https://github.com/MrKai77/DynamicNotchKit")
            )

            AcknowledgementRow(
                name: "mediaremote-adapter",
                license: "BSD 3-Clause",
                url: URL(string: "https://github.com/ungive/mediaremote-adapter")
            )
        }
    }

    // MARK: - Bundle introspection

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

/// Single attribution line with a clickable link that opens the
/// project page in the default browser via `NSWorkspace`.
private struct AcknowledgementRow: View {

    let name: String
    let license: String
    let url: URL?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let url {
                Button("Visit") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }
        }
    }
}
