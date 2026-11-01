//
//  EntryContextMenuPreview.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/19/25.
//

import DataProvider
import SwiftUI

struct EntryContextMenuPreview: View {
    @AppStorage(.libraryLongTermGalleryPosterCachingEnabled)
    private var longTermGalleryPosterCachingEnabled = false

    var snapshot: LibraryEntrySnapshot

    init(entry: AnimeEntry) {
        self.snapshot = LibraryEntrySnapshot(entry: entry)
    }

    init(snapshot: LibraryEntrySnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        KFImageView(
            image: snapshot.displayPosterImage(.posterFull),
            diskCacheExpiration: LibraryImageCacheService.galleryPosterDiskCacheExpiration(
                longTermCachingEnabled: longTermGalleryPosterCachingEnabled
            )
        )
        .scaledToFit()
    }
}
