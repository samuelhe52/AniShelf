//
//  AnimeEntry+DebugStringConvertible.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/19.
//

import Foundation

extension AnimeEntry {
    public var debugDescription: String {
        """
        AnimeEntry(
          name: "\(name)",
          overview: "\(overview ?? "nil")",
          onAirDate: \(onAirDate?.description ?? "nil"),
          type: \(type),
          linkToDetails: \(linkToDetails?.absoluteString ?? "nil"),
          posterPath: \(posterPath ?? "nil"),
          backdropPath: \(backdropPath ?? "nil"),
          tmdbID: \(tmdbID),
          dateSaved: \(dateSaved),
          dateStarted: \(dateStarted?.description ?? "nil"),
          dateFinished: \(dateFinished?.description ?? "nil"),
          isDateTrackingEnabled: \(isDateTrackingEnabled),
          favorite: \(favorite),
          status: \(watchStatus)
        )
        """
    }
}
