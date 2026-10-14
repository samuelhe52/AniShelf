//
//  LibraryEntryTrackingChange.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import Combine
import DataProvider
import Foundation

/// A tracking change saved outside the entry detail, such as by a Shortcuts action.
///
/// An open detail keeps a soft-undo baseline, and "Discard Changes" writes it back. Each
/// `EntryDetailSession` observes this broadcast and copies only the changed fields into its
/// baseline, so a discard keeps the outside change and still undoes the user's own edits.
///
/// Unchecked because `UserEntryInfo` is a plain value type from another module that does not
/// declare `Sendable`.
struct LibraryEntryTrackingChange: @unchecked Sendable {
    enum Field: Hashable {
        case watchStatus
        case dateStarted
        case dateFinished
        case rewatch
        case episodeProgress(seasonNumber: Int)
        case favorite
        case score
    }

    static let notificationName = Notification.Name("LibraryEntryTrackingChange")
    private static let userInfoKey = "change"

    let identity: LibraryEntryIdentity
    let fields: Set<Field>
    /// The entry's values after the change.
    let userInfo: UserEntryInfo
    let trackingUpdatedAt: Date?

    /// Describes what changed between two snapshots of the same entry.
    init?(
        identity: LibraryEntryIdentity,
        before: UserEntryInfo,
        after: UserEntryInfo,
        trackingUpdatedAt: Date?
    ) {
        var fields = Set<Field>()
        if before.watchStatus != after.watchStatus { fields.insert(.watchStatus) }
        if before.dateStarted != after.dateStarted { fields.insert(.dateStarted) }
        if before.dateFinished != after.dateFinished { fields.insert(.dateFinished) }
        if before.isRewatching != after.isRewatching || before.rewatchCount != after.rewatchCount {
            fields.insert(.rewatch)
        }
        if before.favorite != after.favorite { fields.insert(.favorite) }
        if before.score != after.score { fields.insert(.score) }
        let seasonNumbers = Set((before.episodeProgresses + after.episodeProgresses).map(\.seasonNumber))
        for seasonNumber in seasonNumbers
        where Self.progress(in: before, season: seasonNumber) != Self.progress(in: after, season: seasonNumber) {
            fields.insert(.episodeProgress(seasonNumber: seasonNumber))
        }
        guard !fields.isEmpty else { return nil }

        self.identity = identity
        self.fields = fields
        self.userInfo = after
        self.trackingUpdatedAt = trackingUpdatedAt
    }

    /// Copies the changed fields into `baseline`, leaving every other field alone.
    func apply(to baseline: inout UserEntryInfo) {
        for field in fields {
            switch field {
            case .watchStatus:
                baseline.watchStatus = userInfo.watchStatus
            case .dateStarted:
                baseline.dateStarted = userInfo.dateStarted
            case .dateFinished:
                baseline.dateFinished = userInfo.dateFinished
            case .rewatch:
                baseline.isRewatching = userInfo.isRewatching
                baseline.rewatchCount = userInfo.rewatchCount
            case .episodeProgress(let seasonNumber):
                baseline.episodeProgresses.removeAll { $0.seasonNumber == seasonNumber }
                if let progress = Self.progress(in: userInfo, season: seasonNumber) {
                    baseline.episodeProgresses.append(progress)
                    baseline.episodeProgresses.sort { $0.seasonNumber < $1.seasonNumber }
                }
            case .favorite:
                baseline.favorite = userInfo.favorite
            case .score:
                baseline.score = userInfo.score
            }
        }
    }

    @MainActor
    func post(to notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(
            name: Self.notificationName,
            object: nil,
            userInfo: [Self.userInfoKey: self]
        )
    }

    /// Delivers changes on the main actor. Posting happens on the main actor, so delivery is synchronous.
    static func observe(
        notificationCenter: NotificationCenter = .default,
        handler: @escaping @MainActor (LibraryEntryTrackingChange) -> Void
    ) -> AnyCancellable {
        notificationCenter
            .publisher(for: notificationName)
            .compactMap { $0.userInfo?[userInfoKey] as? LibraryEntryTrackingChange }
            .sink { change in
                MainActor.assumeIsolated {
                    handler(change)
                }
            }
    }

    private static func progress(
        in userInfo: UserEntryInfo,
        season seasonNumber: Int
    ) -> UserEntryInfo.EpisodeProgressSnapshot? {
        userInfo.episodeProgresses.first { $0.seasonNumber == seasonNumber }
    }
}
