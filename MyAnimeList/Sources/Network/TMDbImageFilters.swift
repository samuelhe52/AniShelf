//
//  TMDbImageFilters.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/6.
//

import Foundation
import TMDb

enum TMDbImageFilters {
    static let supportedImageLanguageCodes = ["ja", "en", "zh"]

    static var movie: MovieImageFilter {
        MovieImageFilter(languages: supportedImageLanguageCodes)
    }

    static var tvSeries: TVSeriesImageFilter {
        TVSeriesImageFilter(languages: supportedImageLanguageCodes)
    }

    static var tvSeason: TVSeasonImageFilter {
        TVSeasonImageFilter(languages: supportedImageLanguageCodes)
    }
}
