//
//  TMDbSearchContent.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/5.
//

import Collections
import SwiftUI

/// View responsible for displaying TMDb search results and handling TMDb-specific interactions.
struct TMDbSearchContent: View {
    @Environment(TMDbSearchService.self) private var tmdbSearchService: TMDbSearchService
    @Binding var language: Language

    let onRetry: () -> Void
    let onDuplicateTapped: (Int) -> Void
    let checkDuplicate: (Int) -> Bool

    var body: some View {
        VStack {
            switch tmdbSearchService.status {
            case .loaded:
                List {
                    languagePicker
                    results
                }
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .error(let error):
                Spacer()
                VStack {
                    Button("Reload", systemImage: "arrow.clockwise.circle", action: onRetry)
                        .padding(.bottom)
                    Text("An error occurred while loading results.")
                    Text("Check your internet connection.")
                        .padding(.bottom)
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                }
                .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            submitMenu
                .offset(y: -30)
        }
        .animation(.default, value: tmdbSearchService.status)
    }

    @ViewBuilder
    private var languagePicker: some View {
        Picker("Language", selection: $language) {
            ForEach(Language.allCases, id: \.rawValue) { language in
                Text(language.localizedStringResource).tag(language)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if tmdbSearchService.movieResults.isEmpty && tmdbSearchService.seriesResults.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term"))
        } else {
            seriesResults
            movieResults
        }
    }

    private var alreadyAddedMessage: LocalizedStringKey { "Already in library." }

    @ViewBuilder private var seriesResults: some View {
        if !tmdbSearchService.seriesResults.isEmpty {
            Section("TV Series") {
                ForEach(tmdbSearchService.seriesResults.prefix(8), id: \.tmdbID) { series in
                    let isDuplicate = checkDuplicate(series.tmdbID)
                    SeriesResultItem(series: series)
                        .indicateAlreadyAdded(
                            added: isDuplicate,
                            message: alreadyAddedMessage
                        )
                        .onTapGesture {
                            if isDuplicate { onDuplicateTapped(series.tmdbID) }
                        }
                }
            }
        }
    }

    @ViewBuilder private var movieResults: some View {
        if !tmdbSearchService.movieResults.isEmpty {
            Section("Movies") {
                ForEach(tmdbSearchService.movieResults.prefix(8), id: \.tmdbID) { movie in
                    let isDuplicate = checkDuplicate(movie.tmdbID)
                    MovieResultItem(movie: movie)
                        .indicateAlreadyAdded(
                            added: isDuplicate,
                            message: alreadyAddedMessage
                        )
                        .onTapGesture {
                            if isDuplicate { onDuplicateTapped(movie.tmdbID) }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var submitMenu: some View {
        if tmdbSearchService.registeredCount != 0 {
            Button("Add To Library...") {
                tmdbSearchService.submit()
            }
            .buttonStyle(.glassProminent)
            .shadow(color: .blue, radius: 5)
            .transition(.opacity.animation(.interactiveSpring(duration: 0.3)))
        }
    }

}

fileprivate struct AlreadyAddedIndicatorModifier: ViewModifier {
    var added: Bool
    var message: LocalizedStringKey

    func body(content: Content) -> some View {
        if added {
            content
                .blur(radius: 3)
                .disabled(true)
                .overlay {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .glassEffect(.regular)
                        .shadow(radius: 5)
                        .font(.callout)
                }
        } else {
            content
        }
    }
}

extension View {
    fileprivate func indicateAlreadyAdded(
        added: Bool = false,
        message: LocalizedStringKey
    ) -> some View {
        modifier(AlreadyAddedIndicatorModifier(added: added, message: message))
    }
}
