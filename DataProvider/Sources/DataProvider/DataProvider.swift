//
//  DataProvider.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/5.
//

import Foundation
import SwiftData
import os

let dataProviderLogger = Logger(
    subsystem: .moduleIdentifier,
    category: "DataProvider"
)

/// The current schema version used by the data provider.
public typealias CurrentSchema = SchemaV2_8_0

/// The current anime entry type used by the data provider.
public typealias AnimeEntry = CurrentSchema.AnimeEntry
public typealias AnimeEntryDetail = CurrentSchema.AnimeEntryDetail
public typealias AnimeEntryCharacter = CurrentSchema.AnimeEntryCharacter
public typealias AnimeEntryStaff = CurrentSchema.AnimeEntryStaff
public typealias AnimeEntryStaffJob = CurrentSchema.AnimeEntryStaffJob
public typealias AnimeEntrySeasonSummary = CurrentSchema.AnimeEntrySeasonSummary
public typealias AnimeEntryEpisodeSummary = CurrentSchema.AnimeEntryEpisodeSummary
public typealias AnimeEntryEpisodeProgress = CurrentSchema.AnimeEntryEpisodeProgress

@usableFromInline
let persistenStoreURL = URL.applicationSupportDirectory
    .appendingPathComponent("DataProvider")
    .appendingPathComponent("mal.store")

/// A data provider for SwiftData model containers and data operations, stored in MainActor.
@MainActor public final class DataProvider {
    /// The result of opening the app's shared persistent store during startup.
    public static let startupBootstrap = bootstrap()

    /// The default shared instance of the data provider.
    public static var `default`: DataProvider {
        startupBootstrap.provider
    }

    /// A preview instance of the data provider that uses in-memory storage.
    public static let forPreview = DataProvider(inMemory: true)

    /// The shared model container used for data persistence.
    public private(set) var sharedModelContainer: ModelContainer

    /// The data handler instance for performing data operations.
    public private(set) var dataHandler: DataHandler

    /// Whether this instance's data is stored in memory.
    public let inMemory: Bool

    /// The URL of the persistent store used by the model container.
    public let url: URL

    /// Creates a new data provider instance.
    /// - Parameters:
    ///     - inMemory: If true, uses in-memory storage instead of persistent storage.
    ///     - url: The URL of the persistent store.
    /// - Important: This initializer will fatalError if the model container cannot be created.
    ///              This is intentional as the app cannot function without proper data storage.
    public init(inMemory: Bool = false, url: URL = persistenStoreURL) {
        // Data migration happens here
        let container: ModelContainer
        do {
            container = try Self.createModelContainer(inMemory: inMemory, url: url)
        } catch {
            Self.logContainerCreationFailure(error, url: url, operation: "create")
            fatalError("Could not create ModelContainer: \(error)")
        }
        self.inMemory = inMemory
        self.sharedModelContainer = container
        self.dataHandler = .init(modelContainer: container)
        self.url = url
    }

    init(container: ModelContainer, inMemory: Bool, url: URL) {
        self.inMemory = inMemory
        self.sharedModelContainer = container
        self.dataHandler = .init(modelContainer: container)
        self.url = url
    }

    /// Tears down the existing model container and re-initializes it from the persistent store.
    ///
    /// This is crucial for applying changes after a restore operation.
    public func reloadDataStore() {
        setupContainer()
    }

    /// Sets up the model container.
    ///
    /// This will fatalError if the container cannot be created.
    private func setupContainer() {
        // Data migration happens here
        do {
            sharedModelContainer = try Self.createModelContainer(inMemory: inMemory, url: url)
        } catch {
            Self.logContainerCreationFailure(error, url: url, operation: "reload")
            fatalError("Could not create or reload ModelContainer: \(error)")
        }
        dataHandler = .init(modelContainer: sharedModelContainer)
    }

    static func createModelContainer(
        inMemory: Bool = false,
        url: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let modelConfiguration: ModelConfiguration
        if !inMemory {
            try createParentDirectoryIfNeeded(for: url)
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        } else {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlan.self,
            configurations: modelConfiguration)
    }

    private static func createParentDirectoryIfNeeded(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    static func logContainerCreationFailure(
        _ error: Error,
        url: URL,
        operation: String
    ) {
        dataProviderLogger.critical(
            """
            Failed to \(operation, privacy: .public) SwiftData ModelContainer \
            at \(url.path(percentEncoded: false), privacy: .public): \
            \(String(describing: error), privacy: .public)
            """
        )
    }

    /// Fetches persistent models of a certain type.
    public func getModels<T: PersistentModel>(
        ofType: T.Type,
        predicate: Predicate<T>? = nil,
        fetchLimit: Int? = nil
    ) throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        if let fetchLimit {
            descriptor.fetchLimit = fetchLimit
        }
        return try sharedModelContainer.mainContext.fetch(descriptor)
    }

    /// Gets all persistent models of a certain type.
    public func getAllModels<T: PersistentModel>(ofType: T.Type, predicate: Predicate<T>? = nil) throws -> [T] {
        try getModels(ofType: ofType, predicate: predicate)
    }
}
