//
//  EntryDetailBroadcastSearchSheet.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/16.
//

import Foundation
import Kingfisher
import SwiftUI

struct EntryDetailBroadcastSearchSheet: View {
    private struct SearchRequest: Equatable {
        let id = UUID()
        let query: String
    }

    private enum SearchState: Equatable {
        case idle
        case loading
        case loaded([TVMazeShow])
        case failed
    }

    private let contentAnimation: Animation = .default

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let model: EntryDetailBroadcastModel
    let onSelect: (TVMazeShow) -> Void

    @State private var query: String
    @State private var request: SearchRequest?
    @State private var state: SearchState = .idle
    @State private var pendingResult: TVMazeShow?
    @State private var selectionFailed = false

    init(
        model: EntryDetailBroadcastModel,
        initialQuery: String,
        onSelect: @escaping (TVMazeShow) -> Void
    ) {
        self.model = model
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            searchContent
                .navigationTitle(EntryDetailL10n.searchTVMaze)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(EntryDetailL10n.close)
                    }
                }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(EntryDetailL10n.searchAnimePrompt)
        )
        .onSubmit(of: .search, submitSearch)
        .task(id: request?.id) {
            guard let request else { return }
            do {
                let results = try await model.searchTitleCandidates(named: request.query)
                try Task.checkCancellation()
                state = .loaded(results)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.request?.id == request.id else { return }
                state = .failed
            }
        }
        .task(id: pendingResult?.id) {
            guard let pendingResult else { return }
            do {
                guard let candidate = try await model.hydrateTitleCandidate(id: pendingResult.id)
                else {
                    selectionFailed = true
                    self.pendingResult = nil
                    return
                }
                try Task.checkCancellation()
                onSelect(candidate)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                selectionFailed = true
                self.pendingResult = nil
            }
        }
        .alert(EntryDetailL10n.couldNotLoadAirtime, isPresented: $selectionFailed) {
            Button(EntryDetailL10n.close, role: .cancel) {}
        }
        .presentationSizing(.page)
    }

    @ViewBuilder
    private var searchContent: some View {
        ZStack {
            switch state {
            case .idle:
                ContentUnavailableView {
                    Label(EntryDetailL10n.searchTVMaze, systemImage: "magnifyingglass")
                } description: {
                    Text(EntryDetailL10n.searchTVMazeHelp)
                }
                .transition(.opacity)
            case .loading:
                ProgressView(EntryDetailL10n.searchingTVMaze)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            case .loaded(let results):
                if results.isEmpty {
                    ContentUnavailableView {
                        Label(EntryDetailL10n.noResults, systemImage: "magnifyingglass")
                    } description: {
                        Text(EntryDetailL10n.tryDifferentSearchTerm)
                    }
                    .transition(.opacity)
                } else {
                    List(results) { result in
                        Button {
                            pendingResult = result
                        } label: {
                            searchResultRow(result)
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingResult != nil)
                    }
                    .listStyle(.inset)
                    .preferredNavigationBarScrollEdgeEffect()
                    .transition(.opacity)
                }
            case .failed:
                ContentUnavailableView {
                    Label(
                        EntryDetailL10n.couldNotFindMatch,
                        systemImage: "wifi.exclamationmark"
                    )
                } actions: {
                    Button(EntryDetailL10n.tryAgain, action: submitSearch)
                        .buttonStyle(.borderedProminent)
                }
                .transition(.opacity)
            }
        }
        .animation(contentAnimation, value: state)
        .overlay {
            if pendingResult != nil {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .animation(contentAnimation, value: pendingResult != nil)
    }

    private func searchResultRow(_ result: TVMazeShow) -> some View {
        HStack(spacing: 14) {
            KFImageView(
                url: result.fullImageURL,
                targetWidth: 160,
                diskCacheExpiration: .transient
            )
            .scaledToFill()
            .frame(width: 64, height: 96)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(result.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                let metadata = searchResultMetadata(result)
                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private func searchResultMetadata(_ result: TVMazeShow) -> [String] {
        var metadata: [String] = []
        if let premiered = result.premiered {
            metadata.append(String(premiered.prefix(4)))
        }
        if let language = result.language {
            metadata.append(
                EntryDetailBroadcastFormatting.localizedLanguageName(
                    language,
                    locale: locale
                )
            )
        }
        return metadata
    }

    private func submitSearch() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            request = nil
            state = .idle
            return
        }
        pendingResult = nil
        state = .loading
        request = SearchRequest(query: normalizedQuery)
    }
}
