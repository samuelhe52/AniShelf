//
//  AppReviewPromptControllerTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/11.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

@MainActor
struct AppReviewPromptControllerTests {
    @Test func eligibilityRequiresEveryBoundary() {
        let harness = Harness()
        qualifyEngagement(harness)

        harness.clock.date = harness.start.addingTimeInterval(7 * .day - 1)
        #expect(!harness.controller.isEligible)

        harness.clock.date = harness.start.addingTimeInterval(7 * .day)
        #expect(harness.controller.isEligible)
    }

    @Test func distinctActiveDaysNeedNotBeConsecutiveAndOnlyCreditOncePerDay() {
        let harness = Harness()
        for offset in [0, 2, 5, 9, 14] {
            harness.clock.date = harness.start.addingTimeInterval(Double(offset) * .day)
            harness.controller.recordActiveLibraryDay()
            harness.controller.recordActiveLibraryDay()
        }

        #expect(harness.controller.activeDayCount == 5)
    }

    @Test func scoreAndActionBoundariesAreIndependent() {
        let scoreHarness = Harness()
        recordFiveDays(scoreHarness)
        scoreHarness.controller.record(.regularSearchAdd)
        scoreHarness.controller.record(.entryShare(entryID: movieIdentity(1)))
        scoreHarness.controller.record(.multiSelectAction)
        #expect(scoreHarness.controller.score == 6)
        #expect(scoreHarness.controller.qualifyingActionCount == 3)
        #expect(!scoreHarness.controller.isEligible)

        scoreHarness.controller.record(.entryShare(entryID: movieIdentity(2)))
        #expect(scoreHarness.controller.score == 8)
        #expect(scoreHarness.controller.isEligible)

        let actionHarness = Harness()
        recordFiveDays(actionHarness)
        actionHarness.controller.record(.entryWatched(entryID: movieIdentity(1)))
        actionHarness.controller.record(.batchSearchAdd)
        actionHarness.controller.record(.entryWatched(entryID: movieIdentity(1)))
        #expect(actionHarness.controller.score == 6)
        #expect(actionHarness.controller.qualifyingActionCount == 2)
        #expect(!actionHarness.controller.isEligible)
    }

    @Test func actionsUseExactWeightsSuccessOnlyAndDeduplicatePerCycle() {
        let harness = Harness()
        harness.controller.record(.regularSearchAdd)
        harness.controller.record(.entryShare(entryID: movieIdentity(10)))
        harness.controller.record(.entryShare(entryID: movieIdentity(10)))
        harness.controller.record(.entryWatched(entryID: movieIdentity(10)))
        harness.controller.record(.entryWatched(entryID: movieIdentity(10)))
        harness.controller.record(.multiSelectAction)
        harness.controller.record(.batchSearchAdd)
        harness.controller.record(.batchSearchAdd, succeeded: false)

        #expect(harness.controller.score == 12)
        #expect(harness.controller.qualifyingActionCount == 5)
    }

    @Test func requestResetsCycleAndAppliesNinetyDayCooldown() {
        let harness = Harness()
        qualifyEngagement(harness)
        #expect(harness.controller.prepareForRequest())
        #expect(harness.controller.activeDayCount == 0)
        #expect(harness.controller.score == 0)
        #expect(harness.controller.qualifyingActionCount == 0)

        qualifyEngagement(harness)
        harness.clock.date = harness.controller.lastRequestDate!.addingTimeInterval(90 * .day - 1)
        #expect(!harness.controller.isEligible)
        harness.clock.date = harness.controller.lastRequestDate!.addingTimeInterval(90 * .day)
        #expect(harness.controller.isEligible)
    }

    @Test func resetRequiresFiveNewActiveDaysAndClearsEntryDeduplication() {
        let harness = Harness()
        qualifyEngagement(harness)
        #expect(harness.controller.prepareForRequest())

        harness.clock.date = harness.controller.lastRequestDate!.addingTimeInterval(90 * .day)
        harness.controller.record(.entryShare(entryID: movieIdentity(1)))
        harness.controller.record(.entryWatched(entryID: movieIdentity(2)))
        harness.controller.record(.multiSelectAction)
        for offset in 0..<4 {
            harness.clock.date = harness.controller.lastRequestDate!.addingTimeInterval(
                Double(90 + offset) * .day)
            harness.controller.recordActiveLibraryDay()
        }
        #expect(!harness.controller.isEligible)
        harness.clock.date = harness.controller.lastRequestDate!.addingTimeInterval(94 * .day)
        harness.controller.recordActiveLibraryDay()
        #expect(harness.controller.isEligible)
    }

    @Test func cancelledPresentationLeavesEligibilityForLaterSafeRequest() {
        let harness = Harness()
        qualifyEngagement(harness)
        harness.controller.scheduleRequestIfEligible()
        let token = harness.controller.scheduledRequestToken

        // Background cancellation never calls prepareForRequest.
        #expect(token != nil)
        #expect(harness.controller.isEligible)
        #expect(harness.controller.lastRequestDate == nil)

        #expect(harness.controller.prepareForRequest())
        #expect(harness.controller.lastRequestDate != nil)
    }

    @Test func typedEntryIdentitiesDoNotCollideAcrossEntryTypes() {
        let harness = Harness()
        let movie = LibraryEntryIdentity(entryType: .movie, tmdbID: 42)
        let series = LibraryEntryIdentity(entryType: .series, tmdbID: 42)

        harness.controller.record(.entryShare(entryID: movie))
        harness.controller.record(.entryShare(entryID: series))
        harness.controller.record(.entryShare(entryID: movie))

        #expect(harness.controller.score == 4)
        #expect(harness.controller.qualifyingActionCount == 2)
    }

    private func qualifyEngagement(_ harness: Harness) {
        recordFiveDays(harness)
        harness.controller.record(.entryShare(entryID: movieIdentity(1)))
        harness.controller.record(.entryWatched(entryID: movieIdentity(2)))
        harness.controller.record(.multiSelectAction)
    }

    private func recordFiveDays(_ harness: Harness) {
        for offset in 0..<5 {
            harness.clock.date = harness.start.addingTimeInterval(Double(offset) * .day)
            harness.controller.recordActiveLibraryDay()
        }
        harness.clock.date = harness.start.addingTimeInterval(7 * .day)
    }

    private func movieIdentity(_ tmdbID: Int) -> LibraryEntryIdentity {
        LibraryEntryIdentity(entryType: .movie, tmdbID: tmdbID)
    }
}

@MainActor
fileprivate final class Harness {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let clock: TestClock
    let controller: AppReviewPromptController

    init() {
        let suiteName = "AppReviewPromptControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let clock = TestClock(date: start)
        self.clock = clock
        controller = AppReviewPromptController(
            defaults: defaults,
            calendar: Calendar(identifier: .gregorian),
            now: { clock.date }
        )
    }
}

fileprivate final class TestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

extension TimeInterval {
    fileprivate static let day: TimeInterval = 24 * 60 * 60
}
