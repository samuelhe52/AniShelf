//
//  MyAnimeListApp.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import SwiftData
import SwiftUI

@main
struct MyAnimeListApp: App {
    @State var libraryStore: LibraryStore = .init(dataProvider: .default)
    @State var keyStorage: TMDbAPIKeyStorage = .init()
    @State var whatsNew: WhatsNewController = .init()
    @AppStorage(.preferredAnimeInfoLanguage) var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let key = keyStorage.key, !key.isEmpty {
                    LibraryView()
                        .onAppear {
                            libraryStore.language = followsSystemLanguage ? .current : preferredLanguage
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                } else {
                    TMDbAPIOnboardingView()
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                }
            }
            .environment(libraryStore)
            .environment(keyStorage)
            .environment(whatsNew)
            .environment(\.dataHandler, DataProvider.default.dataHandler)
            .sheet(item: presentedWhatsNewEntry) { entry in
                NavigationStack {
                    WhatsNewRootSheet(
                        entry: entry,
                        settingsActions: .init(store: libraryStore),
                        onDismiss: { whatsNew.dismissPresentedEntry() }
                    )
                }
                .presentationDetents([.large])
            }
            .onAppear(perform: updateWhatsNewPresentation)
            .onChange(of: keyStorage.key) { _, _ in
                updateWhatsNewPresentation()
            }
            .globalToasts()
        }
    }

    private var presentedWhatsNewEntry: Binding<WhatsNewEntry?> {
        Binding(
            get: { whatsNew.presentedEntry },
            set: { newValue in
                if let newValue {
                    whatsNew.presentedEntry = newValue
                } else {
                    whatsNew.dismissPresentedEntry()
                }
            }
        )
    }

    private func updateWhatsNewPresentation() {
        whatsNew.presentIfNeeded(allowsAutoPresentation: hasTMDbAPIKey)
    }

    private var hasTMDbAPIKey: Bool {
        guard let key = keyStorage.key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

fileprivate struct WhatsNewRootSheet: View {
    let entry: WhatsNewEntry
    let settingsActions: LibraryProfileSettingsActions
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        WhatsNewView(
            entry: entry,
            actionRunner: settingsActions.makeWhatsNewActionRunner(
                openURL: { url in
                    openURL(url)
                }
            ),
            onDismiss: onDismiss
        )
    }
}
