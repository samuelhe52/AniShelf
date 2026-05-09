//
//  SeriesResultItem.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import DataProvider
import Kingfisher
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "SeriesResultItem")

struct SeriesResultItem: View {
    @Environment(TMDbSearchService.self) var service
    @AppStorage(.searchTMDbLanguage) private var language: Language = .english
    let series: BasicInfo
    var initiallySelected: Bool = false
    @State private var resultOption: ResultOption = .series
    @State private var seasons: [BasicInfo] = []
    @State private var seasonFetchStatus: SeasonFetchStatus = .notStarted

    var body: some View {
        HStack {
            KFImageView(url: series.posterURL, diskCacheExpiration: .shortTerm)
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 80, height: 120)
            VStack(alignment: .leading) {
                infosAndSelection
                resultOptionsView
            }
        }
        .onChange(of: resultOption) {
            service.unregister(info: series)
            for season in seasons {
                service.unregister(info: season)
            }
            if resultOption == .season && seasons.isEmpty {
                guard seasonFetchStatus == .notStarted else { return }
                logger.info("Fetching seasons for entry: \(series.tmdbID)")
                Task {
                    seasonFetchStatus = .fetching
                    seasons = await service.fetchSeasons(for: series, language: language)
                    logger.info("Fetched \(seasons.count) seasons for entry: \(series.tmdbID)")
                    seasonFetchStatus = .fetched
                }
            }
        }
    }

    @ViewBuilder
    private var infosAndSelection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text(series.name)
                    .bold()
                    .lineLimit(1)
                if let date = series.onAirDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .padding(.bottom, 1)
                }
            }
            Spacer()
            selectionIndicator
        }
        Text(series.overview ?? "No overview available")
            .font(.caption2)
            .foregroundStyle(.gray)
            .lineLimit(3)
    }

    @ViewBuilder
    private var resultOptionsView: some View {
        Picker(selection: $resultOption) {
            ForEach(ResultOption.allCases, id: \.hashValue) { option in
                switch option {
                case .series: Text("Series").tag(option)
                case .season: Text("Season").tag(option)
                }
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if resultOption == .series {
            ActionToggle(
                isOn: initiallySelected,
                on: { service.register(info: series) },
                off: { service.unregister(info: series) },
                label: { Image(systemName: "checkmark") }
            )
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .frame(height: 0)
        } else {
            SeasonSelector(
                seasons: seasons, register: service.register, unregister: service.unregister
            )
            .padding(.trailing, 7)
            .disabled(seasons.isEmpty)
            .animation(.default, value: seasons.isEmpty)
        }
    }

    enum ResultOption: CaseIterable, Equatable {
        case series
        case season
    }

    enum SeasonFetchStatus {
        case notStarted
        case fetching
        case fetched
    }
}

fileprivate struct SeasonSelector: View {
    let seasons: [BasicInfo]
    var register: (BasicInfo) -> Void
    var unregister: (BasicInfo) -> Void
    @State private var selectedSeasonIDs: Set<Int> = []

    var body: some View {
        Menu {
            ForEach(seasons, id: \.tmdbID) { season in
                let selected = selectedSeasonIDs.contains(season.tmdbID)
                if let seasonNumber = season.type.seasonNumber {
                    Button {
                        if !selected {
                            register(season)
                            selectedSeasonIDs.insert(season.tmdbID)
                        } else {
                            unregister(season)
                            selectedSeasonIDs.remove(season.tmdbID)
                        }
                    } label: {
                        let title: LocalizedStringKey =
                            seasonNumber != 0 ? "Season \(seasonNumber)" : "Specials"
                        if !selected {
                            Text(title)
                        } else {
                            Label(title, systemImage: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(selectedSeasonIDs.count)")
                .font(.system(size: 18, design: .monospaced))
        }
        .padding(9)
        .background(in: .circle)
        .backgroundStyle(
            selectedSeasonIDs.isEmpty ? Color(uiColor: .systemGray5) : .blue.opacity(0.2)
        )
        .frame(height: 0)
        .animation(.smooth(duration: 0.2), value: selectedSeasonIDs)
        .menuActionDismissBehavior(.disabled)
        .sensoryFeedback(.selection, trigger: selectedSeasonIDs)
    }
}
