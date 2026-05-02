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
    @AppStorage(.preferredAnimeInfoLanguage) var language: Language = .current

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let key = keyStorage.key, !key.isEmpty {
                    LibraryView(store: libraryStore)
                        .onAppear { libraryStore.language = language }
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                } else {
                    TMDbAPIOnboardingView()
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                }
            }
            .environment(keyStorage)
            .environment(\.dataHandler, DataProvider.default.dataHandler)
            .globalToasts()
        }
    }
}
