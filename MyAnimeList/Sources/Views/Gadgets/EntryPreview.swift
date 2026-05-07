//
//  EntryContextMenuPreview.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/19/25.
//

import DataProvider
import SwiftUI

struct EntryContextMenuPreview: View {
    var snapshot: LibraryEntrySnapshot

    init(entry: AnimeEntry) {
        self.snapshot = LibraryEntrySnapshot(entry: entry)
    }

    init(snapshot: LibraryEntrySnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        KFImageView(url: snapshot.posterURL, diskCacheExpiration: .longTerm)
            .scaledToFit()
    }
}
