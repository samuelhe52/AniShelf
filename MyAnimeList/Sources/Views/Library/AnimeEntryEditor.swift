//
//  AnimeEntryEditor.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/20.
//

import AlertToast
import DataProvider
import SHContainers
import SwiftData
import SwiftUI
import os

typealias WatchedStatus = AnimeEntry.WatchStatus
fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "AnimeEntryEditor")

struct AnimeEntryEditor: View {
    @Environment(\.dataHandler) var dataHandler
    @Environment(\.locale) var locale
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(\.libraryStore) var libraryStore
    @AppStorage(.preferredAnimeInfoLanguage) private var language: Language = .current
    @Bindable var entry: AnimeEntry

    @State private var showPosterSelectionView: Bool = false
    @State private var showFavoritedToast: Bool = false
    @State private var showNavigationTitle: Bool = false
    @State private var originalUserInfo: UserEntryInfo
    @State private var showCancelEditsConfirmation: Bool = false

    @State private var conversionInProgress: Bool = false
    @State private var showSeasonPicker: Bool = false
    @State private var isFetchingSeasons: Bool = false
    @State private var seasonNumberOptions: [Int] = []

    init(entry: AnimeEntry) {
        self.entry = entry
        self._originalUserInfo = .init(initialValue: entry.userInfo)
    }

    var body: some View {
        SHForm(alignment: .leading) {
            navigationHeader
            SHSection("Notes") {
                PlaceholderTextEditor(
                    text: $entry.notes,
                    placeholder: "Write some thoughts..."
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .frame(height: 150)
            }
            SHSection("Watch Status", alignment: .center) {
                AnimeEntryWatchedStatusPicker(for: entry)
                    .pickerStyle(.segmented)
                AnimeEntryDatePickers(entry: entry)
            }
        }
        .navigationTitle(showNavigationTitle ? entry.name : "")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismissAction)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    guard entry.userInfoHasChanges(comparedTo: originalUserInfo) else {
                        dismiss()
                        return
                    }
                    showCancelEditsConfirmation = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                convertButton
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPosterSelectionView) {
            NavigationStack {
                PosterSelectionView(
                    tmdbID: entry.tmdbID,
                    type: entry.type
                ) { url in
                    if url != entry.posterURL {
                        entry.usingCustomPoster = true
                    }
                    entry.posterURL = url
                }
                .navigationTitle("Change Poster")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showPosterSelectionView = false
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Convert to which season?",
            isPresented: $showSeasonPicker,
            titleVisibility: .visible
        ) {
            if isFetchingSeasons {
                ProgressView()
            } else if seasonNumberOptions.isEmpty {
                Button("No seasons available", role: .cancel) {}
            } else {
                ForEach(seasonNumberOptions, id: \.self) { seasonNumber in
                    Button("Season \(seasonNumber)") {
                        Task { await convertSeriesToSeason(seasonNumber: seasonNumber) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard all changes?", isPresented: $showCancelEditsConfirmation) {
            Button("Discard", role: .destructive) {
                do {
                    entry.updateUserInfo(from: originalUserInfo)
                    try modelContext.save()
                } catch {
                    ToastCenter.global.completionState = .failed(message: error.localizedDescription)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .toast(
            isPresenting: $showFavoritedToast, duration: 1.5, offsetY: 35,
            alert: {
                let favoritedMessage: LocalizedStringResource = "Favorited"
                let unFavoritedMessage: LocalizedStringResource = "Unfavorited"
                return AlertToast(
                    displayMode: .hud,
                    type: .systemImage(entry.favorite ? "heart.fill" : "heart.slash.fill", .primary),
                    titleResource: entry.favorite ? favoritedMessage : unFavoritedMessage)
            }
        )
        .sensoryFeedback(.lighterImpact, trigger: entry.favorite)
    }

    private var navigationHeader: some View {
        HStack(alignment: .top) {
            KFImageView(url: entry.posterURL, targetWidth: 300, diskCacheExpiration: .longTerm)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 120)
                .overlay(alignment: .bottomTrailing) {
                    AnimeTypeIndicator(type: entry.type, padding: 3)
                        .font(.caption2)
                }
                .contextMenu {
                    Button("Change Poster", systemImage: "photo") {
                        showPosterSelectionView = true
                    }
                } preview: {
                    EntryContextMenuPreview(
                        entry: entry,
                        showTypeIndicator: false
                    )
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        name
                        seasonNumberAndDate
                    }
                    Spacer()
                    favoriteButton
                }
                if let overview = entry.displayOverview {
                    Text(overview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: 140)
                }
            }
        }
    }

    @ViewBuilder
    private var seasonNumberAndDate: some View {
        HStack(alignment: .center) {
            if let seasonNumber = entry.seasonNumber {
                Text("Season \(seasonNumber)")
            }
            if let onAirDate = entry.onAirDate {
                Text(monthAndYearDateFormatter.string(from: onAirDate))
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var name: some View {
        Text(entry.displayName)
            .font(.headline)
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                showNavigationTitle = !visible
            }
            .lineLimit(1)
    }

    private var favoriteButton: some View {
        EntryFavoriteButton(favorited: entry.favorite) {
            withAnimation(.spring(duration: 0.2)) {
                dataHandler?.toggleFavorite(entry: entry)
                showFavoritedToast = true
            }
        }
        .font(.title2)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    private var convertButton: some View {
        Button("Convert") {
            Task { await handleConvertTap() }
        }
        .disabled(conversionInProgress)
        .opacity(conversionInProgress ? 0.5 : 1)
    }

    private var monthAndYearDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY.MM"
        return formatter
    }

    private var parentSeriesName: String? { entry.parentSeriesEntry?.name }

    private func dismissAction() {
        do {
            try modelContext.save()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        dismiss()
    }

    private func handleConvertTap() async {
        guard !conversionInProgress else { return }
        switch entry.type {
        case .series:
            await presentSeasonPicker()
        case .season:
            await convertSeasonToSeries()
        case .movie:
            ToastCenter.global.completionState = .failed("Movies cannot be converted")
        }
    }

    private func presentSeasonPicker() async {
        isFetchingSeasons = true
        conversionInProgress = true
        do {
            let infoFetcher = InfoFetcher()
            let series = try await infoFetcher.tvSeries(
                entry.tmdbID,
                language: language)
            seasonNumberOptions =
                series.seasons?
                .map(\.seasonNumber)
                .sorted() ?? []
            showSeasonPicker = true
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        isFetchingSeasons = false
        conversionInProgress = false
    }

    private func convertSeasonToSeries() async {
        guard let store = libraryStore else {
            ToastCenter.global.completionState = .failed("Library is unavailable")
            return
        }
        guard case .season(_, _) = entry.type else { return }
        conversionInProgress = true
        do {
            try await store.convertSeasonToSeries(entry, language: language)
            ToastCenter.global.completionState = .completed("Converted to series")
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversionInProgress = false
    }

    private func convertSeriesToSeason(seasonNumber: Int) async {
        guard let store = libraryStore else {
            ToastCenter.global.completionState = .failed("Library is unavailable")
            return
        }
        conversionInProgress = true
        do {
            try await store.convertSeriesToSeason(
                entry,
                seasonNumber: seasonNumber,
                language: language)
            ToastCenter.global.completionState = .completed("Converted to season")
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversionInProgress = false
    }
}

struct AnimeEntryWatchedStatusPicker: View {
    var entry: AnimeEntry
    @Environment(\.dataHandler) var dataHandler

    init(for entry: AnimeEntry) {
        self.entry = entry
    }

    private var watchedStatusBinding: Binding<WatchedStatus> {
        Binding(
            get: {
                entry.watchStatus
            },
            set: {
                entry.watchStatus = $0
                switch $0 {
                case .watched:
                    entry.dateFinished = .now
                case .watching:
                    entry.dateStarted = .now
                    entry.dateFinished = nil
                default: break
                }
            })
    }

    var body: some View {
        Picker(selection: watchedStatusBinding) {
            Text("Plan to Watch").tag(WatchedStatus.planToWatch)
            Text("Watching").tag(WatchedStatus.watching)
            Text("Watched").tag(WatchedStatus.watched)
        } label: {
        }
    }
}

struct AnimeEntryDatePickers: View {
    var entry: AnimeEntry
    var labelsHidden: Bool = false

    private var dateStartedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateStarted ?? .now
            },
            set: {
                entry.dateStarted = $0
            })
    }

    private var dateFinishedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateFinished ?? .now
            },
            set: {
                entry.dateFinished = $0
                if $0 < .now {
                    entry.watchStatus = .watched
                }
            })
    }

    var body: some View {
        HStack {
            Spacer()
            DatePicker(
                selection: dateStartedBinding,
                in: Date.distantPast...(entry.dateFinished ?? .now),
                displayedComponents: [.date]
            ) {
                Text("Date Started")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "ellipsis")
                .alignmentGuide(VerticalAlignment.center) { d in
                    labelsHidden ? d[VerticalAlignment.center] : -6
                }
                .foregroundStyle(.secondary)
            DatePicker(
                selection: dateFinishedBinding,
                in: (entry.dateStarted ?? .now)...Date.distantFuture,
                displayedComponents: [.date]
            ) {
                Text("Date Finished")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .datePickerStyle(.vertical(labelsHidden: labelsHidden))
    }
}

#Preview {
    @Previewable @State var dataProvider = DataProvider.forPreview
    @Previewable @State var entry: AnimeEntry = .template(id: 1)
    NavigationStack {
        AnimeEntryEditor(entry: entry)
            .environment(\.dataHandler, dataProvider.dataHandler)
            .onAppear {
                dataProvider.generateEntriesForPreview()
                let entries = try? dataProvider.getAllModels(ofType: AnimeEntry.self)
                entry = entries?.first ?? .template(id: 124)
            }
    }
}
