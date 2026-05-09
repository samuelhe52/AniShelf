//
//  LibraryExportManager.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import DataProvider
import Foundation
import ZIPFoundation

enum LibraryExportFormat: String, CaseIterable, Identifiable {
    case plainText
    case csv
    case tsv
    case json
    case excel

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .plainText:
            "txt"
        case .csv:
            "csv"
        case .tsv:
            "tsv"
        case .json:
            "json"
        case .excel:
            "xlsx"
        }
    }
}

enum LibraryExportError: LocalizedError {
    case exportDirectoryCreationFailed
    case fileWriteFailed
    case archiveCreationFailed

    var errorDescription: String? {
        switch self {
        case .exportDirectoryCreationFailed:
            "Could not create the temporary export directory."
        case .fileWriteFailed:
            "Could not write the exported library file."
        case .archiveCreationFailed:
            "Could not create the Excel workbook."
        }
    }
}

struct LibraryExportPayload: Codable, Equatable {
    let app: String
    let formatVersion: Int
    let exportedAt: String
    let entryCount: Int
    let entries: [LibraryExportRecord]
}

struct LibraryExportRecord: Codable, Equatable {
    let title: String
    let parentSeriesTitle: String?
    let releaseYear: Int?
    let releaseDate: String?
    let animeType: String
    let seasonNumber: Int?
    let detailsURL: String?
    let dateSaved: String
    let watchStatus: String
    let dateStarted: String?
    let dateFinished: String?
    let score: Int?
    let favorite: Bool
    let notes: String
    let usingCustomPoster: Bool

    fileprivate static let headerFields = [
        "title",
        "parent_series_title",
        "release_year",
        "release_date",
        "anime_type",
        "season_number",
        "details_url",
        "date_saved",
        "watch_status",
        "date_started",
        "date_finished",
        "score",
        "favorite",
        "notes",
        "using_custom_poster"
    ]

    init(entry: AnimeEntry) {
        title = entry.name
        parentSeriesTitle = entry.parentSeriesEntry?.name
        releaseYear = Self.releaseYear(from: entry.onAirDate)
        releaseDate = Self.releaseDateString(from: entry.onAirDate)
        seasonNumber = entry.type.seasonNumber
        detailsURL = entry.linkToDetails?.absoluteString
        dateSaved = Self.timestampString(from: entry.dateSaved)
        watchStatus = Self.watchStatusString(for: entry.watchStatus)
        dateStarted = Self.optionalTimestampString(from: entry.dateStarted)
        dateFinished = Self.optionalTimestampString(from: entry.dateFinished)
        score = entry.score
        favorite = entry.favorite
        notes = entry.notes
        usingCustomPoster = entry.usingCustomPoster

        switch entry.type {
        case .movie:
            animeType = "movie"
        case .series:
            animeType = "series"
        case .season:
            animeType = "season"
        }
    }

    fileprivate var delimitedFields: [String] {
        [
            title,
            parentSeriesTitle ?? "",
            releaseYear.map(String.init) ?? "",
            releaseDate ?? "",
            animeType,
            seasonNumber.map(String.init) ?? "",
            detailsURL ?? "",
            dateSaved,
            watchStatus,
            dateStarted ?? "",
            dateFinished ?? "",
            score.map(String.init) ?? "",
            favorite ? "true" : "false",
            notes,
            usingCustomPoster ? "true" : "false"
        ]
    }

    private static func releaseYear(from date: Date?) -> Int? {
        guard let date else { return nil }
        return utcCalendar().component(.year, from: date)
    }

    private static func releaseDateString(from date: Date?) -> String? {
        guard let date else { return nil }
        return makeReleaseDateFormatter().string(from: date)
    }

    private static func timestampString(from date: Date) -> String {
        makeTimestampFormatter().string(from: date)
    }

    private static func optionalTimestampString(from date: Date?) -> String? {
        guard let date else { return nil }
        return timestampString(from: date)
    }

    private static func watchStatusString(for status: AnimeEntry.WatchStatus) -> String {
        switch status {
        case .planToWatch:
            "planned"
        case .watching:
            "watching"
        case .watched:
            "watched"
        case .dropped:
            "dropped"
        }
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func makeReleaseDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        let calendar = utcCalendar()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

@MainActor
final class LibraryExportManager {
    private let exportDate: Date
    private let fileManager: FileManager

    init(exportDate: Date = .now, fileManager: FileManager = .default) {
        self.exportDate = exportDate
        self.fileManager = fileManager
    }

    func createExport(for entries: [AnimeEntry], format: LibraryExportFormat) throws -> URL {
        let payload = LibraryExportPayload(
            app: "AniShelf",
            formatVersion: 1,
            exportedAt: Self.exportTimestampString(from: exportDate),
            entryCount: entries.count(where: \.onDisplay),
            entries: makeRecords(from: entries)
        )

        let exportDirectoryURL = fileManager.temporaryDirectory.appending(
            path: "AniShelf-Exports",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(
                at: exportDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw LibraryExportError.exportDirectoryCreationFailed
        }

        let exportURL = exportDirectoryURL.appending(
            path: exportFileName(for: format),
            directoryHint: .notDirectory
        )

        if fileManager.fileExists(atPath: exportURL.path()) {
            try? fileManager.removeItem(at: exportURL)
        }

        switch format {
        case .excel:
            try writeExcelWorkbook(for: payload, to: exportURL)
        default:
            let data = try exportData(for: payload, format: format)
            do {
                try data.write(to: exportURL, options: [.atomic])
            } catch {
                throw LibraryExportError.fileWriteFailed
            }
        }

        return exportURL
    }

    private func makeRecords(from entries: [AnimeEntry]) -> [LibraryExportRecord] {
        entries
            .filter(\.onDisplay)
            .map(LibraryExportRecord.init)
            .sorted(by: recordSort)
    }

    private func exportData(
        for payload: LibraryExportPayload,
        format: LibraryExportFormat
    ) throws -> Data {
        let string: String
        switch format {
        case .plainText:
            string = plainText(for: payload)
        case .csv:
            string = delimitedText(for: payload.entries, delimiter: ",")
        case .tsv:
            string = delimitedText(for: payload.entries, delimiter: "\t")
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(payload)
        case .excel:
            preconditionFailure("Excel exports are written through writeExcelWorkbook(to:)")
        }

        guard let data = string.data(using: .utf8) else {
            throw LibraryExportError.fileWriteFailed
        }
        return data
    }

    private func plainText(for payload: LibraryExportPayload) -> String {
        let header = [
            "AniShelf Library Export",
            "Exported At: \(payload.exportedAt)",
            "Entry Count: \(payload.entryCount)"
        ].joined(separator: "\n")

        guard !payload.entries.isEmpty else {
            return header + "\n\nNo entries exported.\n"
        }

        let entryText = payload.entries.enumerated().map { index, entry in
            [
                "\(index + 1). \(entry.title)",
                "Type: \(entry.animeType)",
                "Release Year: \(entry.releaseYear.map(String.init) ?? "N/A")",
                "Release Date: \(entry.releaseDate ?? "N/A")",
                "Season Number: \(entry.seasonNumber.map(String.init) ?? "N/A")",
                "Parent Series: \(entry.parentSeriesTitle ?? "N/A")",
                "Details URL: \(entry.detailsURL ?? "N/A")",
                "Saved At: \(entry.dateSaved)",
                "Watch Status: \(entry.watchStatus)",
                "Started At: \(entry.dateStarted ?? "N/A")",
                "Finished At: \(entry.dateFinished ?? "N/A")",
                "Score: \(entry.score.map(String.init) ?? "No score")",
                "Favorite: \(entry.favorite ? "true" : "false")",
                "Custom Poster: \(entry.usingCustomPoster ? "true" : "false")",
                "Notes: \(entry.notes.isEmpty ? "N/A" : entry.notes)"
            ].joined(separator: "\n")
        }

        return header + "\n\n" + entryText.joined(separator: "\n\n")
    }

    private func delimitedText(
        for entries: [LibraryExportRecord],
        delimiter: Character
    ) -> String {
        let rows = [LibraryExportRecord.headerFields] + entries.map(\.delimitedFields)
        return
            rows
            .map { row in
                row.map { escapeDelimitedField($0, delimiter: delimiter) }
                    .joined(separator: String(delimiter))
            }
            .joined(separator: "\n")
            + "\n"
    }

    private func escapeDelimitedField(_ value: String, delimiter: Character) -> String {
        let requiresQuotes =
            value.contains(delimiter)
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard requiresQuotes else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func writeExcelWorkbook(for payload: LibraryExportPayload, to url: URL) throws {
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw LibraryExportError.archiveCreationFailed
        }

        let rows = [LibraryExportRecord.headerFields] + payload.entries.map(\.delimitedFields)
        let files = [
            "[Content_Types].xml": contentTypesXML,
            "_rels/.rels": rootRelationshipsXML,
            "docProps/app.xml": appPropertiesXML,
            "docProps/core.xml": corePropertiesXML(exportedAt: payload.exportedAt),
            "xl/workbook.xml": workbookXML,
            "xl/_rels/workbook.xml.rels": workbookRelationshipsXML,
            "xl/styles.xml": stylesXML,
            "xl/worksheets/sheet1.xml": worksheetXML(rows: rows)
        ]

        do {
            for (path, contents) in files {
                try addArchiveEntry(contents, path: path, to: archive)
            }
        } catch {
            throw LibraryExportError.archiveCreationFailed
        }
    }

    private func addArchiveEntry(
        _ contents: String,
        path: String,
        to archive: Archive
    ) throws {
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }

    private func worksheetXML(rows: [[String]]) -> String {
        let sheetRows = rows.enumerated().map { index, row in
            let cells = row.map { value in
                "<c t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscaped(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(index + 1)\">\(cells)</row>"
        }.joined()

        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetViews>
                <sheetView workbookViewId="0"/>
              </sheetViews>
              <sheetFormatPr defaultRowHeight="15"/>
              <sheetData>\(sheetRows)</sheetData>
            </worksheet>
            """
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func exportFileName(for format: LibraryExportFormat) -> String {
        "AniShelf_Library_Export_\(Self.fileTimestampString(from: exportDate)).\(format.fileExtension)"
    }

    private func recordSort(lhs: LibraryExportRecord, rhs: LibraryExportRecord) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        if lhs.releaseYear != rhs.releaseYear {
            return (lhs.releaseYear ?? Int.min) < (rhs.releaseYear ?? Int.min)
        }

        if lhs.releaseDate != rhs.releaseDate {
            return (lhs.releaseDate ?? "") < (rhs.releaseDate ?? "")
        }

        if lhs.seasonNumber != rhs.seasonNumber {
            return (lhs.seasonNumber ?? Int.min) < (rhs.seasonNumber ?? Int.min)
        }

        if lhs.parentSeriesTitle != rhs.parentSeriesTitle {
            return (lhs.parentSeriesTitle ?? "").localizedCaseInsensitiveCompare(
                rhs.parentSeriesTitle ?? ""
            ) == .orderedAscending
        }

        return lhs.dateSaved < rhs.dateSaved
    }

    private let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

    private let rootRelationshipsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """

    private let appPropertiesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>AniShelf</Application>
        </Properties>
        """

    private func corePropertiesXML(exportedAt: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>AniShelf Library Export</dc:title>
          <dc:creator>AniShelf</dc:creator>
          <cp:lastModifiedBy>AniShelf</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(exportedAt)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(exportedAt)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Library" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """

    private let workbookRelationshipsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

    private let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1">
            <font>
              <sz val="11"/>
              <name val="Aptos"/>
            </font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """

    private static func fileTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func exportTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
