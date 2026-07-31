//
//  AnimeSharingControlsSection.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import DataProvider
import SwiftUI

struct AnimeSharingControlsSection: View {
    let availableLanguages: [Language]
    @Binding var selectedLanguage: Language
    @Binding var usesRoundedCorners: Bool
    @Binding var exportSize: SharingCardExportSize
    let canSelectLanguage: Bool
    let onChangePoster: () -> Void

    var body: some View {
        PopupSectionCard("Customize", systemImage: "slider.horizontal.3") {
            AnimeSharingLanguageControl(
                availableLanguages: availableLanguages,
                selectedLanguage: $selectedLanguage,
                canSelectLanguage: canSelectLanguage
            )

            AnimeSharingAppearanceControl(usesRoundedCorners: $usesRoundedCorners)

            AnimeSharingExportSizeControl(exportSize: $exportSize)

            VStack(alignment: .leading, spacing: 8) {
                Text("Artwork")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onChangePoster) {
                    Label("Change Poster", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct AnimeSharingExportSizeControl: View {
    @Binding var exportSize: SharingCardExportSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Size")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Export Size", selection: $exportSize) {
                ForEach(SharingCardExportSize.allCases, id: \.self) { size in
                    Text(size.localizedName).tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct AnimeSharingAppearanceControl: View {
    @Binding var usesRoundedCorners: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Rounded Corners", isOn: $usesRoundedCorners)
        }
    }
}

struct AnimeSharingLanguageControl: View {
    let availableLanguages: [Language]
    @Binding var selectedLanguage: Language
    let canSelectLanguage: Bool

    var body: some View {
        if canSelectLanguage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language.localizedStringResource).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
