//
//  AnimeSharingSheet.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import DataProvider
import SwiftUI

struct AnimeSharingSheet: View {
    @State private var viewModel: AnimeSharingViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(.preferredAnimeInfoLanguage) private var defaultLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    @State private var showPosterSelection = false

    init(entry: AnimeEntry) {
        _viewModel = State(initialValue: AnimeSharingViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    AnimeSharingPreviewSection(
                        title: viewModel.currentTitle,
                        subtitle: viewModel.previewSubtitle,
                        detail: viewModel.previewDetailLine,
                        aspectRatio: viewModel.previewAspectRatio,
                        image: viewModel.loadedImage,
                        animationTrigger: viewModel.selectedLanguage
                    )

                    AnimeSharingControlsSection(
                        availableLanguages: viewModel.availableLanguages,
                        selectedLanguage: $viewModel.selectedLanguage,
                        canSelectLanguage: viewModel.canSelectLanguage,
                        onChangePoster: { showPosterSelection = true }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if let url = viewModel.renderedImageURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                    } else {
                        Label("Rendering…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showPosterSelection) {
                NavigationStack {
                    PosterSelectionView(
                        tmdbID: viewModel.entry.tmdbID,
                        type: viewModel.entry.type,
                        onPosterSelected: { url in
                            viewModel.updateSelectedPosterURL(url)
                        }
                    )
                    .navigationTitle("Change Poster")
                }
            }
            .task(id: viewModel.renderTrigger) {
                let trigger = viewModel.renderTrigger
                await viewModel.processRenderRequest(for: trigger)
            }
            .onAppear {
                viewModel.applyPreferredLanguage(
                    followsSystemLanguage ? .current : defaultLanguage,
                    respectingCurrentSelection: false
                )
            }
            .onDisappear {
                viewModel.cleanupRenderedFiles()
            }
            .onChange(of: defaultLanguage, initial: false) { _, newValue in
                guard !followsSystemLanguage else { return }
                viewModel.applyPreferredLanguage(newValue, respectingCurrentSelection: true)
            }
            .onChange(of: followsSystemLanguage, initial: false) { _, newValue in
                viewModel.applyPreferredLanguage(
                    newValue ? .current : defaultLanguage,
                    respectingCurrentSelection: true
                )
            }
        }
    }
}

#Preview {
    AnimeSharingSheet(entry: AnimeEntry.frieren)
}
