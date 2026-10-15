//
//  NewerLibraryStoreView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

import SwiftData
import SwiftUI

/// Blocks the app when the library was saved by a newer schema than this build knows.
struct NewerLibraryStoreView: View {
    let storeVersion: Schema.Version

    @Environment(\.openURL) private var openURL

    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6759359144")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.16),
                    Color(uiColor: .systemBackground),
                    Color.teal.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    explanation
                    versions
                    openAppStoreButton
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(LocalizedStringResource("Update AniShelf to Open Your Library"))
                .font(.largeTitle.bold())

            Text(
                LocalizedStringResource(
                    "Your library was saved by a newer version of AniShelf. Update the app to open it."
                )
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            point(
                icon: "lock.shield",
                title: LocalizedStringResource("Your library is safe"),
                detail: LocalizedStringResource(
                    "AniShelf has not changed or moved your library, and iCloud Sync is paused until you update."
                )
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Text(verbatim: Self.appVersion)
                    .monospacedDigit()
            } label: {
                Text(LocalizedStringResource("App Version"))
            }
            LabeledContent {
                Text(verbatim: Self.versionString(storeVersion))
                    .monospacedDigit()
            } label: {
                Text(LocalizedStringResource("Library Data Version"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var openAppStoreButton: some View {
        Button {
            openURL(Self.appStoreURL)
        } label: {
            Text(LocalizedStringResource("Open App Store"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func point(
        icon: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func versionString(_ version: Schema.Version) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }
}

#Preview {
    NewerLibraryStoreView(storeVersion: Schema.Version(2, 9, 0))
}
