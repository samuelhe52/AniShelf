//
//  DataHandler.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/6.
//

import Foundation
import SwiftData
import os

fileprivate let logger = Logger(subsystem: .moduleIdentifier, category: "DataHandler")

@MainActor
public final class DataHandler {
    public let modelContext: ModelContext
    public let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
        self.modelContainer = modelContainer
    }

    public subscript<T: PersistentModel>(_ id: PersistentIdentifier, as type: T.Type) -> T? {
        get {
            let descriptor = FetchDescriptor(
                predicate: #Predicate<T> { $0.persistentModelID == id })
            let model = try? modelContext.fetch(descriptor).first
            return model
        }
    }

    /// Creates a new anime entry in the database.
    /// - Parameter entry: The anime entry to create.
    /// - Returns: The persistent identifier of the newly created entry.
    /// - Throws: An error if the save operation fails.
    @discardableResult
    public func newEntry(_ entry: AnimeEntry) throws -> PersistentIdentifier {
        logger.debug("Creating new anime entry with ID: \(entry.tmdbID), name: \(entry.name)")
        modelContext.insert(entry)
        try modelContext.save()
        return entry.persistentModelID
    }

    /// Marks an anime entry as `planToWatch`.
    /// - Parameter entry: The entry to update.
    public func markEntryAsPlanToWatch(_ entry: AnimeEntry) {
        logger.debug("Marking entry as unwatched: \(entry.tmdbID), name: \(entry.name)")
        entry.setWatchStatus(.planToWatch)
    }

    /// Marks an anime entry as currently watching, setting the start date to now when date tracking is enabled.
    /// - Parameter entry: The entry to update.
    public func markEntryAsWatching(_ entry: AnimeEntry) {
        logger.debug("Marking entry as watching: \(entry.tmdbID), name: \(entry.name)")
        entry.setWatchStatus(.watching)
    }

    /// Marks an anime entry as watched, setting the finish date to now when date tracking is enabled.
    /// - Parameter entry: The entry to update.
    /// - Note: If date tracking is enabled and the entry hasn't been marked as currently watching yet, `dateStarted` will also be set to `.now`.
    public func markEntryAsWatched(_ entry: AnimeEntry) {
        logger.debug("Marking entry as watched: \(entry.tmdbID), name: \(entry.name)")
        entry.setWatchStatus(.watched)
    }

    /// Marks an anime entry as dropped and preserves any existing tracking dates.
    /// - Parameter entry: The entry to update.
    public func markEntryAsDropped(_ entry: AnimeEntry) {
        logger.debug("Marking entry as dropped: \(entry.tmdbID), name: \(entry.name)")
        entry.setWatchStatus(.dropped)
    }

    /// Marks an anime entry as a favorite.
    /// - Parameter entry: The entry to update.
    public func favorite(entry: AnimeEntry) {
        logger.debug("Marking entry as favorite: \(entry.tmdbID), name: \(entry.name)")
        entry.favorite = true
    }

    /// Unmarks an anime entry as a favorite.
    /// - Parameter entry: The entry to update.
    public func unfavorite(entry: AnimeEntry) {
        logger.debug("Unmarking entry as favorite: \(entry.tmdbID), name: \(entry.name)")
        entry.favorite = false
    }

    /// Toggles the favorite status of an anime entry.
    /// - Parameter entry: The entry to update.
    public func toggleFavorite(entry: AnimeEntry) {
        if entry.favorite {
            unfavorite(entry: entry)
        } else {
            favorite(entry: entry)
        }
    }

    /// Deletes a specific anime entry.
    /// - Parameter entry: The entry to delete.
    /// - Throws: An error if the save operation fails.
    public func deleteEntry(_ entry: AnimeEntry) throws {
        logger.debug("Deleting entry \(entry.tmdbID), name: \(entry.name)")
        modelContext.delete(entry)
        try modelContext.save()
    }

    /// Deletes all anime entries from the database.
    /// - Throws: An error if the fetch save operation fails.
    public func deleteAllEntries() throws {
        logger.debug("Deleting all anime entries")
        let descriptor = FetchDescriptor<AnimeEntry>()
        let allEntries = try modelContext.fetch(descriptor)
        for entry in allEntries {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }
}
