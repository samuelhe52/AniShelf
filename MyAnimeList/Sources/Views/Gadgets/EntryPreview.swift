//
//  EntryContextMenuPreview.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/19/25.
//

import DataProvider
import SwiftUI

struct EntryContextMenuPreview: View {
    var entry: AnimeEntry

    var body: some View {
        KFImageView(url: entry.posterURL, diskCacheExpiration: .longTerm)
            .scaledToFit()
    }
}
