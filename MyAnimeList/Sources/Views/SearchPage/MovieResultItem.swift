//
//  MovieResultItem.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import Kingfisher
import SwiftUI

struct MovieResultItem: View {
    let movie: EntryMetadata
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void

    var body: some View {
        HStack {
            KFImageView(url: movie.posterURL, diskCacheExpiration: .shortTerm)
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 60, height: 90)
            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading) {
                        Text(movie.name)
                            .bold()
                            .lineLimit(1)
                        if let date = movie.onAirDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .padding(.bottom, 1)
                        }
                    }
                    Spacer()
                    // Zero height keeps the circular toggle from padding the title block.
                    Toggle(isOn: selectionBinding) {
                        Image(systemName: "checkmark")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .frame(height: 0)
                    .sensoryFeedback(.selection, trigger: isSelected)
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
