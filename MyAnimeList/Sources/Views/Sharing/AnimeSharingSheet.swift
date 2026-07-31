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
    @Namespace private var embeddedPosterPreview

    private let posterFetcher = InfoFetcher()

    private struct Constants {
        static let embeddedBrowserMinimumWidth: CGFloat = 820
        static let contentMaximumWidth: CGFloat = 1_040
        static let horizontalPadding: CGFloat = 20
        static let wideColumnSpacing: CGFloat = 24
        static let previewColumnWidth: CGFloat = 400
    }

    init(entry: AnimeEntry) {
        _viewModel = State(initialValue: AnimeSharingViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if usesEmbeddedPosterBrowser(availableWidth: proxy.size.width) {
                    wideSharingContent
                } else {
                    compactSharingContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Close"))
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
                    originalPosterLanguageCode: originalPosterLanguageCode,
                    showsDismissButton: false,
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

    private var wideSharingContent: some View {
        HStack(spacing: Constants.wideColumnSpacing) {
            GeometryReader { previewProxy in
                ScrollView {
                    sharingPreview
                        .padding(.vertical, 36)
                        .frame(minHeight: previewProxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .frame(width: Constants.previewColumnWidth)

            embeddedControls
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: Constants.contentMaximumWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var compactSharingContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                sharingPreview
                sharingControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .preferredNavigationBarScrollEdgeEffect()
    }

    private var embeddedControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Customize")
                    .font(.title3.weight(.bold))
            }

            AnimeSharingLanguageControl(
                availableLanguages: viewModel.availableLanguages,
                selectedLanguage: $viewModel.selectedLanguage,
                canSelectLanguage: viewModel.canSelectLanguage
            )

            AnimeSharingAppearanceControl(usesRoundedCorners: $viewModel.usesRoundedCorners)

            AnimeSharingExportSizeControl(exportSize: $viewModel.exportSize)

            Divider()

            Text("Artwork")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                PosterBrowserView(
                    tmdbID: viewModel.entry.tmdbID,
                    type: viewModel.entry.type,
                    originalPosterLanguageCode: originalPosterLanguageCode,
                    fetcher: posterFetcher,
                    previewNamespace: embeddedPosterPreview,
                    selectedPosterPath: viewModel.selectedPosterPath,
                    onPosterTap: { poster, _ in
                        selectEmbeddedPoster(poster)
                    }
                )
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .preferredNavigationBarScrollEdgeEffect()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 24)
    }

    private var sharingPreview: some View {
        AnimeSharingPreviewSection(
            title: viewModel.currentTitle,
            subtitle: viewModel.previewSubtitle,
            detail: viewModel.previewDetailLine,
            aspectRatio: viewModel.previewAspectRatio,
            image: viewModel.loadedImage,
            renderedPixelSize: viewModel.renderedPixelSize,
            usesRoundedCorners: viewModel.usesRoundedCorners,
            animationTrigger: viewModel.previewRevision
        )
    }

    private var sharingControls: some View {
        AnimeSharingControlsSection(
            availableLanguages: viewModel.availableLanguages,
            selectedLanguage: $viewModel.selectedLanguage,
            usesRoundedCorners: $viewModel.usesRoundedCorners,
            exportSize: $viewModel.exportSize,
            canSelectLanguage: viewModel.canSelectLanguage,
            onChangePoster: { showPosterSelection = true }
        )
    }

    private var originalPosterLanguageCode: String? {
        viewModel.entry.originalLanguageCode
            ?? viewModel.entry.parentSeriesEntry?.originalLanguageCode
    }

    private func usesEmbeddedPosterBrowser(availableWidth: CGFloat) -> Bool {
        !dynamicTypeSize.isAccessibilitySize
            && availableWidth >= Constants.embeddedBrowserMinimumWidth
    }

    private func selectEmbeddedPoster(_ poster: Poster) {
        let posterPath = TMDbImagePath.storagePath(from: poster.metadata.filePath)
        let originalURL = TMDbImageURLResolver.current.url(for: posterPath, role: .poster)
        withAnimation(.snappy(duration: 0.22)) {
            viewModel.updateSelectedPosterURL(originalURL ?? poster.url)
        }
    }
}

#Preview {
    AnimeSharingSheet(entry: AnimeEntry.frieren)
}
