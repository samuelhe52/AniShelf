//
//  DataProvider+Extensions.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/24.
//

import DataProvider
import Foundation
import SwiftData

extension DataProvider {
    func generateEntriesForPreview() {
        // Ensure we're in preview
        guard inMemory else { return }
        do {
            try dataHandler.newEntry(AnimeEntry.frieren)
            try dataHandler.newEntry(
                AnimeEntry(
                    name: "CLANNAD Season 1",
                    type: .season(seasonNumber: 1, parentSeriesID: 24835),
                    tmdbID: 35033))
            try dataHandler.newEntry(AnimeEntry.yourName)
        } catch {
            print("Error generating preview entries: \(error)")
        }
    }
}
