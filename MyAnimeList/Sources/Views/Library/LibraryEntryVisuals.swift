import DataProvider
import SwiftUI

extension AnimeEntry.WatchStatus {
    var libraryTintColor: Color {
        switch self {
        case .planToWatch:
            .secondary
        case .watching:
            .orange
        case .watched:
            .green
        case .dropped:
            .pink
        }
    }
}

extension AnimeType {
    var libraryLocalizedStringResource: LocalizedStringResource {
        switch self {
        case .movie:
            "Movie"
        case .series:
            "TV Series"
        case .season(let seasonNumber, _):
            if seasonNumber == 0 {
                "Specials"
            } else {
                "Season \(seasonNumber)"
            }
        }
    }
}
