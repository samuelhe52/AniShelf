//
//  AnimeEntry+Helpers.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/10.
//

import Foundation
import SwiftData

extension AnimeEntry {
    /// Whether this entry is a season from a series.
    public var isSeason: Bool {
        switch self.type {
        case .season: return true
        default: return false
        }
    }

    /// The season number of this entry, if it is an `.season`.
    /// - Note: "0" is for "Specials".
    public var seasonNumber: Int? { type.seasonNumber }

    /// The TMDB ID for the parent series of this season, if this entry is of type `.season`.
    public var parentSeriesID: Int? { type.parentSeriesID }

    /// - Note: `dateSaved` and `id` is not updated in this method.
    public func update(from other: AnimeEntry) {
        name = other.name
        nameTranslations = other.nameTranslations
        overview = other.overview
        overviewTranslations = other.overviewTranslations
        onAirDate = other.onAirDate
        type = other.type
        linkToDetails = other.linkToDetails
        posterURL = other.posterURL
        backdropURL = other.backdropURL
        // Date saved and id is not updated.
        dateStarted = other.dateStarted
        dateFinished = other.dateFinished
        favorite = other.favorite
    }

    public static func template(id: Int = 0) -> AnimeEntry {
        .init(name: "Template", type: .movie, tmdbID: id)
    }

    public static var frieren: AnimeEntry {
        AnimeEntry(
            name: "葬送のフリーレン",
            nameTranslations: ["ja-JP": "葬送のフリーレン", "en-US": "Frieren: Beyond Journey's End", "zh-CN": "葬送的芙莉莲"],
            overview:
                "勇者ヒンメルたちと共に、10年に及ぶ冒険の末に魔王を打ち倒し、世界に平和をもたらした魔法使いフリーレン。千年以上生きるエルフである彼女は、ヒンメルたちと再会の約束をし、独り旅に出る。それから50年後、フリーレンはヒンメルのもとを訪ねるが、50年前と変わらぬ彼女に対し、ヒンメルは老い、人生は残りわずかだった。その後、死を迎えたヒンメルを目の当たりにし、これまで“人を知る”ことをしてこなかった自分を痛感し、それを悔いるフリーレンは、“人を知るため”の旅に出る。その旅路には、さまざまな人との出会い、さまざまな出来事が待っていた―。",
            onAirDate: .now,
            type: .series,
            linkToDetails: URL(string: "https://frieren-anime.jp/"),
            posterURL: URL(
                string: "https://image.tmdb.org/t/p/original/dDRiOkCBCkd7w6ysMFr39G16opQ.jpg"),
            backdropURL: URL(
                string: "https://image.tmdb.org/t/p/original/96RT2A47UdzWlUfvIERFyBsLhL2.jpg"),
            tmdbID: 209867,
            dateSaved: .now,
            dateStarted: nil,
            dateFinished: nil,
        )
    }

    public static var yourName: AnimeEntry {
        AnimeEntry(
            name: "君の名は。",
            nameTranslations: [
                "ja-JP": "君の名は。",
                "en-US": "Your Name.",
                "zh-CN": "你的名字。",
            ],
            overview:
                "山深い田舎町で暮らす女子高生の三葉と、東京で暮らす男子高校生の瀧。出会うはずのない二人は、ある日突然入れ替わる不思議な現象をきっかけに、お互いの人生へ深く関わっていく。",
            onAirDate: previewDate(year: 2016, month: 8, day: 26),
            type: .movie,
            linkToDetails: URL(string: "https://kiminonawa-movie.jp/"),
            tmdbID: 372058,
            dateSaved: .now,
            dateStarted: nil,
            dateFinished: nil,
        )
    }

    private static func previewDate(year: Int, month: Int, day: Int) -> Date? {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day))
    }
}

extension Collection where Element == AnimeEntry {
    /// Get an anime entry with the given TMDB ID.
    public func entryWithTMDbID(_ id: Int) -> AnimeEntry? {
        guard id != 0 else { return nil }
        return self.first { $0.tmdbID == id }
    }

    /// Get an anime entry with the given persistent identifier.
    public func entryWithID(_ id: PersistentIdentifier) -> AnimeEntry? {
        self.first { $0.id == id }
    }

    /// Get an anime entry with the given persistent identifier.
    public subscript(id: PersistentIdentifier) -> AnimeEntry? {
        self.first { $0.id == id }
    }
}
