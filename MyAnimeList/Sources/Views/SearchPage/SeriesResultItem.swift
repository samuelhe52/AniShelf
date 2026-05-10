//
//  SeriesResultItem.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import Kingfisher
import SwiftUI

struct SeriesResultItem: View {
    let series: BasicInfo
    let selectionState: TMDbSeriesSelectionState
    let isSeriesSelected: Bool
    let onSeriesSelectionChanged: (Bool) -> Void
    let onSelectionModeChanged: (TMDbSeriesSelectionMode) -> Void
    let onSeasonSelectionChanged: (BasicInfo, Bool) -> Void

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
        Picker(selection: selectionModeBinding) {
            Text(seriesTitleResource).tag(TMDbSeriesSelectionMode.series)
            Text(seasonTitleResource).tag(TMDbSeriesSelectionMode.season)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        switch selectionState.selectedMode {
        case .series:
            Toggle(isOn: seriesSelectionBinding) {
                Image(systemName: "checkmark")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .frame(height: 0)
            .sensoryFeedback(.selection, trigger: isSeriesSelected)
        case .season:
            SeasonSelector(
                seasons: selectionState.seasons,
                selectedSeasonIDs: selectionState.selectedSeasonIDs,
                onSeasonSelectionChanged: onSeasonSelectionChanged
            )
            .padding(.trailing, 7)
            .disabled(
                selectionState.seasonFetchStatus == .fetching || selectionState.seasons.isEmpty
            )
            .animation(.default, value: selectionState.seasons.isEmpty)
        }
    }

    private var selectionModeBinding: Binding<TMDbSeriesSelectionMode> {
        Binding(
            get: { selectionState.selectedMode },
            set: { onSelectionModeChanged($0) }
        )
    }

    private var seriesSelectionBinding: Binding<Bool> {
        Binding(
            get: { isSeriesSelected },
            set: { onSeriesSelectionChanged($0) }
        )
    }

    private var seriesTitleResource: LocalizedStringResource {
        "Series"
    }

    private var seasonTitleResource: LocalizedStringResource {
        "Season"
    }
}

fileprivate struct SeasonSelector: View {
    let seasons: [BasicInfo]
    let selectedSeasonIDs: Set<Int>
    let onSeasonSelectionChanged: (BasicInfo, Bool) -> Void

    var body: some View {
        Menu {
            ForEach(seasons, id: \.tmdbID) { season in
                let selected = selectedSeasonIDs.contains(season.tmdbID)
                if let seasonNumber = season.type.seasonNumber {
                    Button {
                        onSeasonSelectionChanged(season, !selected)
                    } label: {
                        let title: LocalizedStringKey =
                            seasonNumber != 0 ? "Season \(seasonNumber)" : "Specials"
                        if selected {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
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
