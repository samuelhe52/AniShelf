//
//  LibraryDuplicateRepairSheet+Preview.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/29.
//

import DataProvider
import Foundation
import SwiftUI

@MainActor
fileprivate struct LibraryDuplicateRepairSheetPreviewHost: View {
    @State private var store: LibraryStore

    init() {
        _store = State(initialValue: LibraryDuplicateRepairPreviewFixtures.makeStore())
    }

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: duplicateRepairPresented) {
                LibraryDuplicateRepairSheet(store: store)
                    .presentationDetents([.large])
                    .presentationSizing(.page)
            }
    }

    private var duplicateRepairPresented: Binding<Bool> {
        Binding(
            get: { store.requiresDuplicateRepair },
            set: { _ in }
        )
    }
}

@MainActor
fileprivate enum LibraryDuplicateRepairPreviewFixtures {
    static func makeStore() -> LibraryStore {
        let defaults = UserDefaults(suiteName: "LibraryDuplicateRepairSheetPreview")!
        defaults.removePersistentDomain(forName: "LibraryDuplicateRepairSheetPreview")

        let store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: LibraryPreferences(defaults: defaults)
        )
        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = false
        }

        let firstCopy = AnimeEntry(
            name: "Frieren: Beyond Journey's End",
            overview: "The original local copy with completed viewing progress.",
            type: .series,
            tmdbID: 209_867,
            dateSaved: date(day: 22, hour: 9),
            dateFinished: date(day: 23, hour: 21),
            score: 9,
            libraryUpdatedAt: date(day: 23, hour: 21),
            trackingUpdatedAt: date(day: 23, hour: 21)
        )
        firstCopy.watchStatus = .watched
        firstCopy.favorite = true
        firstCopy.notes = "Finished this copy first."

        let secondCopy = AnimeEntry(
            name: "葬送のフリーレン",
            overview: "A conflicting copy with newer notes and tracking state.",
            type: .series,
            tmdbID: 209_867,
            dateSaved: date(day: 25, hour: 14),
            dateStarted: date(day: 24, hour: 20),
            score: 8,
            libraryUpdatedAt: date(day: 27, hour: 18),
            trackingUpdatedAt: date(day: 27, hour: 18)
        )
        secondCopy.watchStatus = .watching
        secondCopy.notes = "Currently rewatching from this copy."

        let recommendedCopy = AnimeEntry(
            name: "Frieren: Beyond Journey's End",
            overview: "The most recently saved copy, shown as the recommended choice.",
            type: .series,
            tmdbID: 209_867,
            dateSaved: date(day: 28, hour: 11),
            score: 10,
            libraryUpdatedAt: date(day: 29, hour: 8),
            trackingUpdatedAt: date(day: 29, hour: 8)
        )
        recommendedCopy.watchStatus = .planToWatch
        recommendedCopy.favorite = true
        recommendedCopy.notes = "Newest stored copy."

        let secondGroupOlderCopy = AnimeEntry(
            name: "The Apothecary Diaries",
            overview: "An older copy in a separate duplicate group.",
            type: .series,
            tmdbID: 220_542,
            dateSaved: date(day: 20, hour: 16),
            dateStarted: date(day: 21, hour: 19),
            score: 8,
            libraryUpdatedAt: date(day: 24, hour: 10),
            trackingUpdatedAt: date(day: 24, hour: 10)
        )
        secondGroupOlderCopy.watchStatus = .watching
        secondGroupOlderCopy.notes = "Paused midway through this copy."

        let secondGroupRecommendedCopy = AnimeEntry(
            name: "薬屋少女的呢喃",
            overview: "The newer copy recommended in the second duplicate group.",
            type: .series,
            tmdbID: 220_542,
            dateSaved: date(day: 26, hour: 12),
            score: 9,
            libraryUpdatedAt: date(day: 29, hour: 12),
            trackingUpdatedAt: date(day: 29, hour: 12)
        )
        secondGroupRecommendedCopy.watchStatus = .planToWatch
        secondGroupRecommendedCopy.favorite = true
        secondGroupRecommendedCopy.notes = "Restart from the newer copy."

        do {
            try store.repository.newEntry(firstCopy)
            try store.repository.newEntry(secondCopy)
            try store.repository.newEntry(recommendedCopy)
            try store.repository.newEntry(secondGroupOlderCopy)
            try store.repository.newEntry(secondGroupRecommendedCopy)
            try store.refreshLibrary()
        } catch {
            assertionFailure("Unable to create duplicate repair preview fixtures: \(error)")
        }

        return store
    }

    private static func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return components.date!
    }
}

#Preview("Duplicate Repair Notice") {
    LibraryDuplicateRepairSheetPreviewHost()
}
