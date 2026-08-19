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
        posterPath = other.posterPath
        backdropPath = other.backdropPath
        usingCustomPoster = other.usingCustomPoster
        customPosterPath = other.customPosterPath
        // Date saved and id is not updated.
        dateStarted = other.dateStarted
        dateFinished = other.dateFinished
        isDateTrackingEnabled = other.isDateTrackingEnabled
        favorite = other.favorite
    }

    public static func template(id: Int = 0) -> AnimeEntry {
        .init(name: "Template", type: .movie, tmdbID: id)
    }

    /// Preview metadata snapshot verified against TMDb on 2026-07-30.
    public static var frieren: AnimeEntry {
        AnimeEntry(
            name: "葬送のフリーレン",
            nameTranslations: ["ja-JP": "葬送のフリーレン", "en-US": "Frieren: Beyond Journey's End", "zh-CN": "葬送的芙莉莲"],
            overview:
                "勇者ヒンメルたちと共に、10年に及ぶ冒険の末に魔王を打ち倒し、世界に平和をもたらした魔法使いフリーレン。千年以上生きるエルフである彼女は、ヒンメルたちと再会の約束をし、独り旅に出る。それから50年後、フリーレンはヒンメルのもとを訪ねるが、50年前と変わらぬ彼女に対し、ヒンメルは老い、人生は残りわずかだった。その後、死を迎えたヒンメルを目の当たりにし、これまで“人を知る”ことをしてこなかった自分を痛感し、それを悔いるフリーレンは、“人を知るため”の旅に出る。その旅路には、さまざまな人との出会い、さまざまな出来事が待っていた―。",
            onAirDate: previewDate(year: 2023, month: 9, day: 29),
            type: .series,
            linkToDetails: URL(string: "https://frieren-anime.jp/"),
            posterPath: "/dhzbCznEzU67RXWYb53fyPe9Keb.jpg",
            backdropPath: "/rBOnrVlck7BIlGeWVlzYiZeg4l2.jpg",
            tmdbID: 209867,
            originalLanguageCode: "ja",
            dateSaved: .now,
            dateStarted: nil,
            dateFinished: nil,
        )
    }

    /// Preview metadata snapshot verified against TMDb on 2026-07-30.
    public static var yourName: AnimeEntry {
        AnimeEntry(
            name: "君の名は。",
            nameTranslations: [
                "ja-JP": "君の名は。",
                "en-US": "Your Name.",
                "zh-CN": "你的名字。"
            ],
            overview:
                "1,000年に1度のすい星来訪が、1か月後に迫る日本。山々に囲まれた田舎町に住む女子高生の三葉は、町長である父の選挙運動や、家系の神社の風習などに鬱屈（うっくつ）していた。それゆえに都会への憧れを強く持っていたが、ある日彼女は自分が都会に暮らしている少年になった夢を見る。夢では東京での生活を楽しみながらも、その不思議な感覚に困惑する三葉。一方、東京在住の男子高校生・瀧も自分が田舎町に生活する少女になった夢を見る。やがて、その奇妙な夢を通じて彼らは引き合うようになっていくが……。",
            onAirDate: previewDate(year: 2016, month: 7, day: 1),
            type: .movie,
            linkToDetails: URL(string: "https://www.kiminona.com/"),
            posterPath: "/yLglTwyFOUZt5fNKm0PWL1PK5gm.jpg",
            backdropPath: "/mMtUybQ6hL24FXo0F3Z4j2KG7kZ.jpg",
            tmdbID: 372058,
            originalLanguageCode: "ja",
            dateSaved: .now,
            dateStarted: nil,
            dateFinished: nil,
        )
    }

    /// Preview metadata snapshot verified against TMDb on 2026-07-30.
    public static var clannadSeasonOne: AnimeEntry {
        AnimeEntry(
            name: "CLANNAD",
            overview:
                "進学校に通う高校3年生の岡崎朋也は、無気力な毎日を送っている。毎日同じことの繰り返し。周りのみんなのように学校生活を楽しむことも出来ず、毎日遅刻ばかり。そのためか、校内では浮いた存在になっていた。ある日、朋也は学校まで続く坂道の下で、一人の少女に出会う。",
            onAirDate: previewDate(year: 2007, month: 10, day: 5),
            type: .season(seasonNumber: 1, parentSeriesID: 24835),
            linkToDetails: URL(string: "https://www.tbs.co.jp/clannad/clannad1/"),
            posterPath: "/ktDb3XeZE2rRYP39Vf7EOAi87KX.jpg",
            backdropPath: "/vB7HwJNhlRA9tPViK32bK0hVCmb.jpg",
            tmdbID: 35033,
            originalLanguageCode: "ja",
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
    /// Gets an anime entry with the given stable library identity.
    public func entry(with identity: LibraryEntryIdentity) -> AnimeEntry? {
        first { $0.libraryIdentity == identity }
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
