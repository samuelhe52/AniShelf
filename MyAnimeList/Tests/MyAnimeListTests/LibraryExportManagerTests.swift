//
//  LibraryExportManagerTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import Testing
import ZIPFoundation

@testable import DataProvider
@testable import MyAnimeList

@MainActor
struct LibraryExportManagerTests {
    @Test func testJSONExportIncludesIdentifyingFieldsAndUserInfo() throws {
        let movie = AnimeEntry(
            name: "Movie Export",
            type: .movie,
            linkToDetails: URL(string: "https://example.com/movie"),
            tmdbID: 101,
            dateSaved: utcDate("2026-05-01T10:15:30Z")
        )
        movie.onAirDate = utcDate("2024-04-05T00:00:00Z")
        movie.setWatchStatus(.watched, now: utcDate("2026-05-03T11:00:00Z"))
        movie.favorite = true
        movie.notes = "Loved it."
        movie.usingCustomPoster = true

        let season = AnimeEntry(
            name: "Season Export",
            type: .season(seasonNumber: 2, parentSeriesID: 202),
            linkToDetails: URL(string: "https://example.com/season"),
            tmdbID: 303,
            dateSaved: utcDate("2026-05-02T09:00:00Z")
        )
        season.onAirDate = utcDate("2025-01-10T00:00:00Z")
        season.parentSeriesEntry = AnimeEntry(name: "Parent Series", type: .series, tmdbID: 202)
        season.setWatchStatus(.watching, now: utcDate("2026-05-04T08:30:00Z"))

        let manager = LibraryExportManager(exportDate: utcDate("2026-05-09T12:00:00Z"))
        let url = try manager.createExport(for: [season, movie], format: .json)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(LibraryExportPayload.self, from: data)
        let exportedMovie = try #require(payload.entries.first(where: { $0.tmdbID == 101 }))
        let exportedSeason = try #require(payload.entries.first(where: { $0.tmdbID == 303 }))

        #expect(url.pathExtension == "json")
        #expect(payload.entryCount == 2)
        #expect(payload.exportedAt == "2026-05-09T12:00:00Z")
        #expect(exportedMovie.releaseYear == 2024)
        #expect(exportedMovie.releaseDate == "2024-04-05")
        #expect(exportedMovie.animeType == "movie")
        #expect(exportedMovie.watchStatus == "watched")
        #expect(exportedMovie.favorite)
        #expect(exportedMovie.notes == "Loved it.")
        #expect(exportedMovie.usingCustomPoster)
        #expect(exportedMovie.dateSaved == "2026-05-01T10:15:30Z")
        #expect(exportedSeason.parentSeriesTitle == "Parent Series")
        #expect(exportedSeason.parentSeriesTMDbID == 202)
        #expect(exportedSeason.seasonNumber == 2)
    }

    @Test func testDelimitedExportsQuoteStructuredNotes() throws {
        let entry = AnimeEntry(
            name: "Delimited Export",
            type: .series,
            tmdbID: 404,
            dateSaved: utcDate("2026-05-01T00:00:00Z")
        )
        entry.notes = "Line 1, with comma\nLine\t2"

        let manager = LibraryExportManager(exportDate: utcDate("2026-05-09T12:00:00Z"))

        let csvURL = try manager.createExport(for: [entry], format: .csv)
        defer { try? FileManager.default.removeItem(at: csvURL) }
        let csv = try String(contentsOf: csvURL)
        #expect(csv.contains("\"Line 1, with comma\nLine\t2\""))

        let tsvURL = try manager.createExport(for: [entry], format: .tsv)
        defer { try? FileManager.default.removeItem(at: tsvURL) }
        let tsv = try String(contentsOf: tsvURL)
        #expect(tsv.contains("\"Line 1, with comma\nLine\t2\""))
    }

    @Test func testExcelExportCreatesWorkbookArchive() throws {
        let entry = AnimeEntry(
            name: "Workbook Export",
            type: .movie,
            tmdbID: 505,
            dateSaved: utcDate("2026-05-01T00:00:00Z")
        )
        entry.notes = "For workbook"

        let manager = LibraryExportManager(exportDate: utcDate("2026-05-09T12:00:00Z"))
        let url = try manager.createExport(for: [entry], format: .excel)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try #require(Archive(url: url, accessMode: .read))
        let worksheetEntry = try #require(archive["xl/worksheets/sheet1.xml"])
        let worksheetXML = try archive.stringContents(of: worksheetEntry)

        #expect(url.pathExtension == "xlsx")
        #expect(archive["xl/workbook.xml"] != nil)
        #expect(archive["[Content_Types].xml"] != nil)
        #expect(worksheetXML.contains("Workbook Export"))
        #expect(worksheetXML.contains("For workbook"))
    }

    private func utcDate(_ timestamp: String) -> Date {
        ISO8601DateFormatter().date(from: timestamp)!
    }
}

extension Archive {
    fileprivate func stringContents(of entry: Entry) throws -> String {
        var data = Data()
        _ = try extract(entry) { chunk in
            data.append(chunk)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
