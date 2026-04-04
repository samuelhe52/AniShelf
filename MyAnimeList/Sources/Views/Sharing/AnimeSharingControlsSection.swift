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
    let canSelectLanguage: Bool
    let onChangePoster: () -> Void

    var body: some View {
        PopupSectionCard("Controls", systemImage: "slider.horizontal.3") {
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
