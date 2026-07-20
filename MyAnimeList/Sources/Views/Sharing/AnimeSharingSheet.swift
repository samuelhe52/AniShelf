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
    @Environment(AppReviewPromptController.self) private var appReview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(.preferredAnimeInfoLanguage) private var defaultLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    @State private var showPosterSelection = false
    @State private var didActivateShare = false

    init(entry: AnimeEntry) {
        _viewModel = State(initialValue: AnimeSharingViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                sharingContent
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 1_040)
                    .frame(maxWidth: .infinity)
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
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                didActivateShare = true
                                appReview.record(
                                    .entryShare(entryID: viewModel.entry.tmdbID),
                                    scheduleRequest: false
                                )
                            }
                        )
                    } else {
                        Label("Rendering…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(isPresented: $showPosterSelection) {
                PosterSelectionView(
                    tmdbID: viewModel.entry.tmdbID,
                    type: viewModel.entry.type,
                    originalPosterLanguageCode: viewModel.entry.originalLanguageCode
                        ?? viewModel.entry.parentSeriesEntry?.originalLanguageCode,
                    onPosterSelected: { url in
                        viewModel.updateSelectedPosterURL(url)
                    }
                )
                .navigationTitle("Change Poster")
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
                if didActivateShare {
                    appReview.scheduleRequestIfEligible()
                }
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
        .presentationSizing(.page)
    }

    @ViewBuilder
    private var sharingContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedSharingContent
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalSharingContent

                stackedSharingContent
            }
        }
    }

    private var horizontalSharingContent: some View {
        HStack(alignment: .center, spacing: 32) {
            sharingPreview
                .frame(width: 420)
            sharingControls
                .frame(width: 320)
        }
        // Keep the full-size preview and controls together. Without this, the
        // HStack can be compressed enough to fit a page sheet while making
        // both panels unnecessarily narrow.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stackedSharingContent: some View {
        VStack(spacing: 24) {
            sharingPreview
            sharingControls
        }
    }

    private var sharingPreview: some View {
        AnimeSharingPreviewSection(
            title: viewModel.currentTitle,
            subtitle: viewModel.previewSubtitle,
            detail: viewModel.previewDetailLine,
            aspectRatio: viewModel.previewAspectRatio,
            image: viewModel.loadedImage,
            animationTrigger: viewModel.selectedLanguage
        )
    }

    private var sharingControls: some View {
        AnimeSharingControlsSection(
            availableLanguages: viewModel.availableLanguages,
            selectedLanguage: $viewModel.selectedLanguage,
            canSelectLanguage: viewModel.canSelectLanguage,
            onChangePoster: { showPosterSelection = true }
        )
    }
}

#Preview {
    AnimeSharingSheet(entry: AnimeEntry.frieren)
}
