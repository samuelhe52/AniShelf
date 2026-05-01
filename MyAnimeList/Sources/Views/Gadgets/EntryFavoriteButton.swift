//
//  EntryFavoriteButton.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/11/25.
//

import SwiftUI

struct EntryFavoriteButton: View {
    let favorited: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(favoriteActionResource)
            } icon: {
                Image(systemName: favorited ? "heart.fill" : "heart")
            }
        }
    }

    private var favoriteActionResource: LocalizedStringResource {
        favorited ? "Unfavorite" : "Favorite"
    }
}
