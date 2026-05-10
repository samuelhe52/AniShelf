//
//  MovieResultItem.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import Kingfisher
import SwiftUI

struct MovieResultItem: View {
    let movie: BasicInfo
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void

    var body: some View {
        HStack {
            KFImageView(url: movie.posterURL, diskCacheExpiration: .shortTerm)
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 60, height: 90)
            VStack(alignment: .leading) {
                HStack {
                    Text(movie.name)
                        .bold()
                        .lineLimit(1)
                    Spacer()
                    Toggle(isOn: selectionBinding) {
                        Image(systemName: "checkmark")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .sensoryFeedback(.selection, trigger: isSelected)
                }
                if let date = movie.onAirDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .padding(.bottom, 1)
                }
                Text(movie.overview ?? "No overview available")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(3)
            }
        }
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { isSelected },
            set: { onSelectionChanged($0) }
        )
    }
}
