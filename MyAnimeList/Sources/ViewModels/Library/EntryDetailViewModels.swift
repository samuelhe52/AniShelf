//
//  EntryDetailViewModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/6.
//

import DataProvider
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EntryDetailViewModel {
    private static let maxDisplayedStaffCount = 24
    private static let prioritizedStaffRoleBuckets: [[String]] = [
        [
            "Director",
            "Series Director",
            "Co-Director",
            "Assistant Director",
            "Directing",
            "Action Director",
            "Storyboard Artist",
            "Storyboard Assistant",
            "Additional Storyboarding"
        ],
        ["Original Story", "Novel", "Comic Book", "Original Concept"],
        ["Series Composition", "Screenplay", "Writer", "Writing"],
        [
            "Character Designer",
            "Original Series Design",
            "Mechanical Designer",
            "Creature Design",
            "Prop Designer",
            "Settings",
            "Art Designer"
        ],
        [
            "Supervising Animation Director",
            "Animation Director",
            "Lead Animator",
            "Key Animation",
            "Opening/Ending Animation"
        ],
        [
            "Supervising Art Director",
            "Art Direction",
            "Assistant Art Director",
            "Art",
            "Background Designer",
            "Color Designer",
            "Concept Artist",
            "Conceptual Design",
            "Production Design",
            "Graphic Designer",
            "Title Designer",
            "Painter"
        ],
        [
            "Director of Photography",
            "Assistant Director of Photography",
            "Camera",
            "Compositing Lead",
            "Compositing Artist",
            "Compositor",
            "Visual Effects",
            "Special Effects",
            "Effects Supervisor",
            "CGI Director",
            "CGI Supervisor",
            "CG Supervisor",
            "CG Artist",
            "3D Director",
            "3D Supervisor",
            "3D Animator",
            "3D Artist",
            "Modeling"
        ],
        [
            "Sound Director",
            "Music",
            "Original Music Composer",
            "Music Director",
            "Music Producer",
            "Music Supervisor",
            "Theme Song Performance",
            "Songs",
            "Musician",
            "Sound",
            "Sound Effects",
            "Sound Mixer",
            "Sound Recordist",
            "Sound Assistant",
            "Foley",
            "Foley Artist"
        ],
        [
            "Producer",
            "Executive Producer",
            "Supervising Producer",
            "Line Producer",
            "Production Supervisor",
            "Production Manager",
            "Co-Producer",
            "Associate Producer",
            "Co-Executive Producer",
            "Development Producer",
            "Production",
            "Production Assistant",
            "Assistant Production Manager"
        ]
    ]
    private static let prioritizedStaffRoleRanks: [String: Int] = {
        var ranks: [String: Int] = [:]
        for (bucketIndex, roles) in prioritizedStaffRoleBuckets.enumerated() {
            for role in roles where ranks[role] == nil {
                ranks[role] = bucketIndex
            }
        }
        return ranks
    }()
    private static let prioritizedStaffRoleOrdersByBucket: [[String: Int]] =
        prioritizedStaffRoleBuckets.map { roles in
            Dictionary(uniqueKeysWithValues: roles.enumerated().map { ($0.element, $0.offset) })
        }
    private static let unprioritizedStaffBucketIndex = prioritizedStaffRoleBuckets.count

    private struct DisplayedStaffRow {
        var id: Int
        var name: String
        var role: String
        var originalIndex: Int
        var bucketIndex: Int
        var profileURL: URL?
    }

    private struct IndexedStaffJob {
        var title: String
        var originalIndex: Int
    }

    private let repository: LibraryRepository
    private let infoFetcher: InfoFetcher

    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var heroImageURL: URL?
    private(set) var logoImageURL: URL?
    private(set) var primaryLinkURL: URL?
    private(set) var displayTitle = ""
    private(set) var subtitleText: String?
    private(set) var metadataLineItems: [String] = []
    private(set) var overviewText = String(localized: EntryDetailL10n.noOverviewAvailable)
    private(set) var genreNames: [String] = []
    private(set) var statCards: [EntryDetailStatCard] = []
    private(set) var characterCards: [EntryDetailPersonCard] = []
    private(set) var staffCards: [EntryDetailPersonCard] = []
    private(set) var seasonCards: [EntryDetailSeasonCard] = []
    private(set) var episodeCards: [EntryDetailEpisodeCard] = []
    private(set) var collapseSeriesSeasonsByDefault = false
    private(set) var characterSectionTitle: LocalizedStringResource =
        EntryDetailL10n.characters

    private var lastRequestKey: String?

    init(repository: LibraryRepository, infoFetcher: InfoFetcher = .init()) {
        self.repository = repository
        self.infoFetcher = infoFetcher
    }

    func load(for entry: AnimeEntry, language: Language, dataHandler: DataHandler?) async {
        let requestKey = "\(entry.tmdbID)-\(language.rawValue)"
        guard lastRequestKey != requestKey else { return }
        lastRequestKey = requestKey

        displayTitle = entry.displayName
        subtitleText = nil
        metadataLineItems = []
        overviewText = entry.displayOverview ?? String(localized: EntryDetailL10n.noOverviewAvailable)
        genreNames = []
        statCards = []
        characterCards = []
        staffCards = []
        seasonCards = []
        episodeCards = []
        collapseSeriesSeasonsByDefault = false
        characterSectionTitle = EntryDetailL10n.characters
        primaryLinkURL = entry.linkToDetails
        heroImageURL = entry.backdropURL ?? entry.posterURL
        logoImageURL = nil
        loadError = nil
        if let detail = entry.detail, detail.language == language.rawValue {
            apply(detail: detail, entry: entry, language: language)
            if detail.logoImageURL != nil {
                isLoading = false
                return
            }
        }

        isLoading = true
        do {
            let detailDTO = try await infoFetcher.detailInfo(
                entryType: entry.type,
                tmdbID: entry.tmdbID,
                language: language
            )
            let detail = entry.replaceDetail(from: detailDTO)
            try? dataHandler?.modelContext.save()
            apply(detail: detail, entry: entry, language: language)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func hasSiblingSeasonEntry(for entry: AnimeEntry) -> Bool {
        guard case .season(_, let parentSeriesID) = entry.type else { return false }

        do {
            let visibleSiblingExists = try repository.visibleLibraryEntries().contains { candidate in
                guard candidate.id != entry.id else { return false }
                guard case .season(_, let candidateParentSeriesID) = candidate.type else {
                    return false
                }
                return candidateParentSeriesID == parentSeriesID
            }

            if visibleSiblingExists {
                return true
            }
        } catch {
            libraryStoreLogger.warning(
                "Failed to check sibling season entries for \(entry.tmdbID, privacy: .public): \(error.localizedDescription)"
            )
        }

        return entry.parentSeriesEntry?.childSeasonEntries.contains(where: { $0.id != entry.id })
            ?? false
    }

    func seasonNumberOptions(for entry: AnimeEntry, language: Language) async throws -> [Int] {
        let series = try await infoFetcher.tvSeries(
            entry.tmdbID,
            language: language
        )
        return series.seasons?.map(\.seasonNumber).sorted() ?? []
    }

    func convertSeasonToSeries(_ entry: AnimeEntry, language: Language) async throws {
        let converter = LibraryEntryConverter(repository: repository)
        try await converter.convertSeasonToSeries(
            entry,
            language: language,
            fetcher: infoFetcher
        )
    }

    func convertSeriesToSeason(
        _ entry: AnimeEntry,
        seasonNumber: Int,
        language: Language
    ) async throws {
        let converter = LibraryEntryConverter(repository: repository)
        try await converter.convertSeriesToSeason(
            entry,
            seasonNumber: seasonNumber,
            language: language,
            fetcher: infoFetcher
        )
    }

    private func apply(detail: AnimeEntryDetail, entry: AnimeEntry, language: Language) {
        displayTitle = detail.title
        subtitleText = detail.subtitle
        overviewText =
            detail.overview ?? entry.displayOverview
            ?? String(localized: EntryDetailL10n.noOverviewAvailable)
        genreNames = Self.localizedGenreNames(detail.genreIDs, language: language)
        heroImageURL = detail.heroImageURL ?? entry.backdropURL ?? entry.posterURL
        logoImageURL = detail.logoImageURL
        primaryLinkURL = detail.primaryLinkURL ?? entry.linkToDetails
        characterSectionTitle = EntryDetailL10n.characters

        metadataLineItems =
            switch entry.type {
            case .movie:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.runtimeMinutes.map(Self.minutesText),
                    detail.status
                ].compactMap(\.self)
            case .series:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.status,
                    detail.seasonCount.map(Self.seasonCountText)
                ].compactMap(\.self)
            case .season:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.episodeCount.map(Self.episodeCountText),
                    detail.status
                ].compactMap(\.self)
            }

        statCards =
            switch entry.type {
            case .movie:
                [
                    detail.voteAverage.map {
                        EntryDetailStatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        EntryDetailStatCard(
                            id: "runtime",
                            title: EntryDetailL10n.runtime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    }
                ].compactMap(\.self)
            case .series, .season:
                [
                    detail.voteAverage.map {
                        EntryDetailStatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.episodeCount.map {
                        EntryDetailStatCard(
                            id: "episodes",
                            title: EntryDetailL10n.episodes,
                            value: "\($0)",
                            symbolName: "play.rectangle.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        EntryDetailStatCard(
                            id: "runtime",
                            title: EntryDetailL10n.averageRuntime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    }
                ].compactMap(\.self)
            }

        characterCards = detail.orderedCharacters.map {
            EntryDetailPersonCard(
                id: $0.id,
                primaryText: $0.characterName,
                secondaryText: $0.actorName,
                profileURL: $0.profileURL
            )
        }
        staffCards = Self.displayedStaffCards(from: detail.orderedStaff, language: language)
        seasonCards = Self.orderedSeasonSummaries(detail.seasons).map {
            EntryDetailSeasonCard(
                id: $0.id,
                seasonNumber: $0.seasonNumber,
                title: $0.title,
                subtitle: Self.seasonLabelText($0.seasonNumber),
                posterURL: $0.posterURL
            )
        }
        collapseSeriesSeasonsByDefault =
            entry.type == .series
            && EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: detail.episodeCount,
                seasonCount: detail.seasonCount,
                seasonCardCount: seasonCards.count
            )
        episodeCards = detail.orderedEpisodes.map {
            EntryDetailEpisodeCard(
                id: $0.id,
                episodeNumber: $0.episodeNumber,
                title: "\($0.episodeNumber). \($0.title)",
                subtitle: $0.airDate?.formatted(date: .abbreviated, time: .omitted)
                    ?? String(localized: EntryDetailL10n.episode),
                imageURL: $0.imageURL
            )
        }
    }

    private static func displayedStaffCards(
        from staff: [AnimeEntryStaff],
        language: Language
    ) -> [EntryDetailPersonCard] {
        displayedStaffRows(from: staff)
            .sorted { lhs, rhs in
                if lhs.bucketIndex == rhs.bucketIndex {
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.bucketIndex < rhs.bucketIndex
            }
            .prefix(maxDisplayedStaffCount)
            .map {
                EntryDetailPersonCard(
                    id: $0.id,
                    primaryText: $0.name,
                    secondaryText: localizedStaffRole($0.role, language: language),
                    profileURL: $0.profileURL
                )
            }
    }

    private static func displayedStaffRows(from staff: [AnimeEntryStaff]) -> [DisplayedStaffRow] {
        staff.enumerated().flatMap { index, staffMember in
            displayedStaffRows(for: staffMember, originalIndex: index)
        }
    }

    private static func displayedStaffRows(
        for staffMember: AnimeEntryStaff,
        originalIndex: Int
    ) -> [DisplayedStaffRow] {
        let bucketedRows = bucketedDisplayedStaffRows(
            for: staffMember,
            originalIndex: originalIndex
        )
        guard bucketedRows.isEmpty else { return bucketedRows }

        return [
            DisplayedStaffRow(
                id: staffMember.id,
                name: staffMember.name,
                role:
                    normalizedNonEmpty(staffMember.role)
                    ?? normalizedNonEmpty(staffMember.department)
                    ?? "Staff",
                originalIndex: originalIndex,
                bucketIndex: staffPriority(
                    role: staffMember.role,
                    department: staffMember.department
                ),
                profileURL: staffMember.profileURL
            )
        ]
    }

    private static func bucketedDisplayedStaffRows(
        for staffMember: AnimeEntryStaff,
        originalIndex: Int
    ) -> [DisplayedStaffRow] {
        let jobs = staffMember.orderedJobs.enumerated().compactMap { offset, job -> IndexedStaffJob? in
            guard let title = normalizedNonEmpty(job.job) else { return nil }
            return IndexedStaffJob(title: title, originalIndex: offset)
        }
        guard !jobs.isEmpty else { return [] }

        var jobsByBucket: [Int: [IndexedStaffJob]] = [:]
        for job in jobs {
            jobsByBucket[staffBucketIndex(for: job.title), default: []].append(job)
        }

        return jobsByBucket.keys.sorted().map { bucketIndex in
            DisplayedStaffRow(
                id: staffDisplayIdentifier(personID: staffMember.id, bucketIndex: bucketIndex),
                name: staffMember.name,
                role: bucketDisplayRole(
                    jobsByBucket[bucketIndex] ?? [],
                    bucketIndex: bucketIndex,
                    department: staffMember.department
                ),
                originalIndex: originalIndex,
                bucketIndex: bucketIndex,
                profileURL: staffMember.profileURL
            )
        }
    }

    private static func staffPriority(role: String, department: String?) -> Int {
        staffRoleComponents(role: role, department: department)
            .map(staffBucketIndex(for:))
            .min()
            ?? unprioritizedStaffBucketIndex
    }

    private static func staffBucketIndex(for roleComponent: String) -> Int {
        prioritizedStaffRoleRanks[roleComponent] ?? unprioritizedStaffBucketIndex
    }

    private static func bucketDisplayRole(
        _ jobs: [IndexedStaffJob],
        bucketIndex: Int,
        department: String?
    ) -> String {
        let orderedTitles = jobs.sorted { lhs, rhs in
            let lhsPriority = staffRolePriority(for: lhs.title, in: bucketIndex)
            let rhsPriority = staffRolePriority(for: rhs.title, in: bucketIndex)
            if lhsPriority == rhsPriority {
                return lhs.originalIndex < rhs.originalIndex
            }
            return lhsPriority < rhsPriority
        }.prefix(2).map(\.title)

        return
            normalizedNonEmpty(orderedTitles.joined(separator: " / "))
            ?? normalizedNonEmpty(department)
            ?? "Staff"
    }

    private static func staffDisplayIdentifier(personID: Int, bucketIndex: Int) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(personID)-\(bucketIndex)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash)
    }

    private static func staffRolePriority(for roleComponent: String, in bucketIndex: Int) -> Int {
        guard bucketIndex < prioritizedStaffRoleOrdersByBucket.count else { return .max }
        return prioritizedStaffRoleOrdersByBucket[bucketIndex][roleComponent] ?? .max
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func staffRoleComponents(role: String, department: String?) -> [String] {
        var components =
            role
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let department {
            let normalizedDepartment = department.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedDepartment.isEmpty && !components.contains(normalizedDepartment) {
                components.append(normalizedDepartment)
            }
        }

        return components
    }
}

@MainActor
@Observable
final class EpisodePreviewViewModel {
    private let detailLoadAnimation: Animation = .easeInOut(duration: 0.3)

    private(set) var overviewText = String(localized: EntryDetailL10n.loading)
    private(set) var isLoading = false

    private var lastRequestKey: String?

    func load(card: EntryDetailEpisodeCard, context: EpisodePreviewContext) async {
        let requestKey =
            "\(context.seriesTMDbID)-\(context.seasonNumber)-\(card.episodeNumber)-\(context.language.rawValue)"
        guard lastRequestKey != requestKey else { return }
        lastRequestKey = requestKey
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try await InfoFetcher().episodePreviewInfo(
                parentSeriesID: context.seriesTMDbID,
                seasonNumber: context.seasonNumber,
                episodeNumber: card.episodeNumber,
                language: context.language
            )
            let resolvedOverviewText =
                detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? detail.overview!
                : String(localized: EntryDetailL10n.noOverviewAvailable)
            withAnimation(detailLoadAnimation) {
                overviewText = resolvedOverviewText
            }
        } catch {
            withAnimation(detailLoadAnimation) {
                overviewText = String(localized: EntryDetailL10n.noOverviewAvailable)
            }
        }
    }
}
