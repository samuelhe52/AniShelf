//
//  AppReviewPromptController.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/11.
//

import DataProvider
import Foundation
import Observation

enum ReviewEngagementAction: Equatable {
    case regularSearchAdd
    case entryShare(entryID: LibraryEntryIdentity)
    case entryWatched(entryID: LibraryEntryIdentity)
    case multiSelectAction
    case batchSearchAdd

    var points: Int {
        switch self {
        case .regularSearchAdd: 1
        case .entryShare: 2
        case .entryWatched, .multiSelectAction, .batchSearchAdd: 3
        }
    }
}

@MainActor @Observable
final class AppReviewPromptController {
    private enum Key {
        static let firstLaunchDate = "AppReview.firstLaunchDate"
        static let activeDays = "AppReview.activeDays"
        static let score = "AppReview.score"
        static let actionCount = "AppReview.actionCount"
        static let sharedEntryIDs = "AppReview.sharedEntryIDs"
        static let watchedEntryIDs = "AppReview.watchedEntryIDs"
        static let lastRequestDate = "AppReview.lastRequestDate"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private(set) var scheduledRequestToken: UUID?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(now(), forKey: Key.firstLaunchDate)
        }
    }

    var isEligible: Bool {
        isEligible(at: now())
    }

    func recordActiveLibraryDay() {
        var days = activeDayIdentifiers
        let identifier = activeDayIdentifier(for: now())
        guard days.insert(identifier).inserted else { return }
        defaults.set(Array(days), forKey: Key.activeDays)
    }

    func record(
        _ action: ReviewEngagementAction,
        succeeded: Bool = true,
        scheduleRequest: Bool = true
    ) {
        guard succeeded, creditIfNeeded(action) else { return }

        defaults.set(score + action.points, forKey: Key.score)
        defaults.set(qualifyingActionCount + 1, forKey: Key.actionCount)
        if scheduleRequest {
            scheduleRequestIfEligible()
        }
    }

    func scheduleRequestIfEligible() {
        guard isEligible else { return }
        scheduledRequestToken = UUID()
    }

    /// Rechecks every gate and resets the engagement cycle immediately before StoreKit is invoked.
    func prepareForRequest() -> Bool {
        let requestDate = now()
        guard isEligible(at: requestDate) else { return false }

        defaults.set(requestDate, forKey: Key.lastRequestDate)
        defaults.removeObject(forKey: Key.activeDays)
        defaults.removeObject(forKey: Key.score)
        defaults.removeObject(forKey: Key.actionCount)
        defaults.removeObject(forKey: Key.sharedEntryIDs)
        defaults.removeObject(forKey: Key.watchedEntryIDs)
        scheduledRequestToken = nil
        return true
    }

    var activeDayCount: Int { activeDayIdentifiers.count }
    var score: Int { defaults.integer(forKey: Key.score) }
    var qualifyingActionCount: Int { defaults.integer(forKey: Key.actionCount) }
    var lastRequestDate: Date? { defaults.object(forKey: Key.lastRequestDate) as? Date }

    private var activeDayIdentifiers: Set<String> {
        Set(defaults.stringArray(forKey: Key.activeDays) ?? [])
    }

    private func isEligible(at date: Date) -> Bool {
        guard let firstLaunchDate = defaults.object(forKey: Key.firstLaunchDate) as? Date,
            date.timeIntervalSince(firstLaunchDate) >= 7 * 24 * 60 * 60,
            activeDayCount >= 5,
            score >= 8,
            qualifyingActionCount >= 3
        else { return false }

        guard let lastRequestDate else { return true }
        return date.timeIntervalSince(lastRequestDate) >= 90 * 24 * 60 * 60
    }

    private func creditIfNeeded(_ action: ReviewEngagementAction) -> Bool {
        switch action {
        case .entryShare(let entryIdentity):
            return insert(entryIdentity, key: Key.sharedEntryIDs)
        case .entryWatched(let entryIdentity):
            return insert(entryIdentity, key: Key.watchedEntryIDs)
        case .regularSearchAdd, .multiSelectAction, .batchSearchAdd:
            return true
        }
    }

    private func insert(_ entryIdentity: LibraryEntryIdentity, key: String) -> Bool {
        var identifiers = Set(defaults.stringArray(forKey: key) ?? [])
        guard identifiers.insert(entryIdentity.rawID).inserted else { return false }
        defaults.set(Array(identifiers), forKey: key)
        return true
    }

    private func activeDayIdentifier(for date: Date) -> String {
        String(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)
    }
}
