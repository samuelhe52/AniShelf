//
//  LibrarySearchContent.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/5.
//

import DataProvider
import SwiftUI

/// View responsible for displaying library search results and handling library-specific interactions.
struct LibrarySearchContent: View {
    @Environment(LibrarySearchService.self) private var librarySearchService: LibrarySearchService
    let onRetry: () -> Void

    var body: some View {
        VStack {
            switch librarySearchService.status {
            case .loaded:
                libraryResults
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
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                }
                .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .listStyle(.inset)
        .animation(.default, value: librarySearchService.status)
    }

    @ViewBuilder
    private var libraryResults: some View {
        if librarySearchService.results.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term"))
        } else {
            List {
                ForEach(librarySearchService.results, id: \.tmdbID) { result in
                    AnimeEntryListRow(
                        entry: result,
                        onTap: {
                            librarySearchService.jumpToEntryInLibrary(result.tmdbID)
                        }
                    )
                }
            }
        }
    }
}
