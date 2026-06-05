//
//  LibraryStore.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import Combine
import DataProvider
import Foundation
import LibrarySync
import SwiftData
import SwiftUI
import os

let libraryStoreLogger = Logger(subsystem: .bundleIdentifier, category: "LibraryStore")

@Observable @MainActor
class LibraryStore {
    // MARK: - Dependencies

    @ObservationIgnored let dataProvider: DataProvider
    @ObservationIgnored let repository: LibraryRepository
    @ObservationIgnored let syncChangeRecorder: LibrarySyncChangeRecorder
    @ObservationIgnored private(set) var syncCoordinator: LibrarySyncCoordinator?
    @ObservationIgnored private var syncScheduler: LibrarySyncScheduler?
    @ObservationIgnored private var ordinarySyncTasks: [UUID: Task<LibrarySyncCoordinator.SyncResult, Never>] =
        [:]
    @ObservationIgnored private var shouldResumeInterruptedCloudSyncBootstrap = false
    @ObservationIgnored let preferences: LibraryPreferences
    @ObservationIgnored private let cloudSyncStateController: LibraryCloudSyncStateController
    @ObservationIgnored private var isApplyingRemoteCloudSyncedPreferences = false
    @ObservationIgnored private var lastObservedCloudSyncedPreferencesHash = ""
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - State

    private(set) var library: [AnimeEntry]
    @ObservationIgnored var infoFetcher: InfoFetcher
    var language: Language = .resolvedAnimeInfoLanguage()
    private(set) var libraryCloudSyncStatus: LibraryCloudSyncStatus

    // MARK: - Filtering & Sorting State

    var filters: Set<AnimeFilter> = []
    var hideDroppedByDefault: Bool = false {
        willSet {
            preferences.saveHideDroppedByDefault(newValue)
            libraryStoreLogger.debug("Updated hide dropped by default to \(newValue)")
        }
    }
    var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus = .planToWatch {
        willSet {
            preferences.saveDefaultWatchStatus(newValue)
            libraryStoreLogger.debug("Updated default new entry watch status to \(newValue.preferenceValue)")
        }
    }
    var defaultFilters: Set<AnimeFilter> = [] {
        willSet {
            preferences.saveDefaultFilters(newValue)
            libraryStoreLogger.debug("Updated default filters to \(newValue.map(\.id).sorted())")
        }
        didSet {
            guard defaultFilters != oldValue else { return }
            applyDefaultFilters()
        }
    }
    var autoPrefetchImagesOnAddAndRestore: Bool = false {
        willSet {
            preferences.saveAutoPrefetchImagesOnAddAndRestore(newValue)
            libraryStoreLogger.debug("Updated auto prefetch images on add and restore to \(newValue)")
        }
    }
    var groupStrategy: LibraryGroupStrategy = .none {
        willSet {
            preferences.saveGroupStrategy(newValue)
            libraryStoreLogger.debug("Updated group strategy to \(newValue.rawValue)")
        }
    }
    var sortStrategy: AnimeSortStrategy = .dateStarted {
        willSet {
            preferences.saveSortStrategy(newValue)
            libraryStoreLogger.debug("Updated sort strategy to \(newValue.rawValue)")
        }
    }
    var sortReversed: Bool = true {
        willSet {
            preferences.saveSortReversed(newValue)
            libraryStoreLogger.debug("Updated sort reversed to \(newValue)")
        }
    }

    var libraryOnDisplay: [AnimeEntry] {
        filterAndSort(library)
    }

    var libraryDisplayItems: [LibraryEntryDisplayItem] {
        libraryOnDisplay.map(LibraryEntryDisplayItem.init)
    }

    init(
        dataProvider: DataProvider,
        preferences: LibraryPreferences = .init(),
        hasTMDbAPIKey: @escaping @MainActor () -> Bool = {
            guard let key = TMDbAPIKeyStorage().retrieveKey() else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    ) {
        self.dataProvider = dataProvider
        let syncChangeRecorder = LibrarySyncChangeRecorder(dataProvider: dataProvider)
        let repository = LibraryRepository(
            dataProvider: dataProvider,
            syncChangeRecorder: syncChangeRecorder
        )
        self.syncChangeRecorder = syncChangeRecorder
        self.repository = repository
        self.preferences = preferences
        let snapshot = preferences.load()
        self.cloudSyncStateController = .init(
            preferences: preferences,
            hasTMDbAPIKey: hasTMDbAPIKey
        )
        self.infoFetcher = .init()
        self.library = []
        self.libraryCloudSyncStatus = snapshot.cloudSyncStatus
        self.shouldResumeInterruptedCloudSyncBootstrap =
            snapshot.cloudSyncStatus.isEnabled && snapshot.cloudSyncStatus.bootstrapState == .running
        reloadPersistedPreferences()
        lastObservedCloudSyncedPreferencesHash = preferences.cloudSyncedSettingsPayloadHash()
        setupUpdateLibrary()
        setupTMDbAPIConfigurationChangeMonitor()
        if !dataProvider.inMemory {
            setupCloudSyncedPreferencesMonitor()
        }
        try? refreshLibrary()
        self.syncCoordinator = LibrarySyncCoordinator(store: self)
        setupLibrarySyncScheduling()
    }

    func reloadPersistedPreferences() {
        let snapshot = preferences.load()
        language = snapshot.resolvedAnimeInfoLanguage
        if groupStrategy != snapshot.groupStrategy {
            groupStrategy = snapshot.groupStrategy
        }
        if sortStrategy != snapshot.sortStrategy {
            sortStrategy = snapshot.sortStrategy
        }
        if sortReversed != snapshot.sortReversed {
            sortReversed = snapshot.sortReversed
        }
        if hideDroppedByDefault != snapshot.hideDroppedByDefault {
            hideDroppedByDefault = snapshot.hideDroppedByDefault
        }
        if defaultNewEntryWatchStatus != snapshot.defaultWatchStatus {
            defaultNewEntryWatchStatus = snapshot.defaultWatchStatus
        }
        if defaultFilters != snapshot.defaultFilters {
            defaultFilters = snapshot.defaultFilters
        }
        if autoPrefetchImagesOnAddAndRestore != snapshot.autoPrefetchImagesOnAddAndRestore {
            autoPrefetchImagesOnAddAndRestore = snapshot.autoPrefetchImagesOnAddAndRestore
        }
        if libraryCloudSyncStatus != snapshot.cloudSyncStatus {
            libraryCloudSyncStatus = snapshot.cloudSyncStatus
        }

        applyDefaultFilters()
    }

    func applyRemoteCloudSyncedPreferences(_ snapshot: LibrarySettingsSyncSnapshot) {
        isApplyingRemoteCloudSyncedPreferences = true
        preferences.applyCloudSyncedSettingsSnapshot(snapshot)
        preferences.saveCloudSyncedDefaultsUpdatedAt(snapshot.updatedAt)
        lastObservedCloudSyncedPreferencesHash = preferences.cloudSyncedSettingsPayloadHash()
        reloadPersistedPreferences()
        infoFetcher = .init()
        isApplyingRemoteCloudSyncedPreferences = false
    }

    // MARK: - Library Loading & Observers

    func refreshLibrary() throws {
        libraryStoreLogger.debug("[\(Date().debugDescription)] Refreshing library...")
        let entries = try repository.visibleLibraryEntries()
        withAnimation {
            library = entries
        }
    }

    func setupUpdateLibrary() {
        NotificationCenter.default
            .publisher(for: ModelContext.didSave)
            .sink { [weak self] _ in
                do {
                    try self?.refreshLibrary()
                } catch {
                    libraryStoreLogger.error("Error refreshing library: \(error)")
                }
            }
            .store(in: &cancellables)
    }

    func rebuildSyncChangeTracking() {
        syncChangeRecorder.rebuildBaseline()
    }

    func syncLibrary(trigger: LibrarySyncCoordinator.Trigger) {
        Task {
            await performLibrarySyncResult(trigger: trigger)
        }
    }

    func flushPendingLocalLibrarySync() {
        syncScheduler?.flushLocalDirtyQueueSync()
    }

    @discardableResult
    func performLibrarySync(trigger: LibrarySyncCoordinator.Trigger) async -> Bool {
        await performLibrarySyncResult(trigger: trigger).succeeded
    }

    func performLibrarySyncResult(trigger: LibrarySyncCoordinator.Trigger) async
        -> LibrarySyncCoordinator.SyncResult
    {
        guard let syncCoordinator else { return .permanentFailure }
        guard !Task.isCancelled else { return .skipped(.disabled) }
        if shouldResumeInterruptedCloudSyncBootstrap {
            shouldResumeInterruptedCloudSyncBootstrap = false
            return await bootstrapLibraryCloudSyncEnablement()
        }

        let taskID = UUID()
        let syncTask = Task {
            await syncCoordinator.syncResult(trigger: trigger)
        }
        ordinarySyncTasks[taskID] = syncTask

        let result = await withTaskCancellationHandler {
            await syncTask.value
        } onCancel: {
            syncTask.cancel()
        }
        ordinarySyncTasks[taskID] = nil
        guard libraryCloudSyncStatus.isEnabled else { return .skipped(.disabled) }
        return result
    }

    @discardableResult
    func enableLibraryCloudSync() async -> Bool {
        await bootstrapLibraryCloudSyncEnablement().succeeded
    }

    private func bootstrapLibraryCloudSyncEnablement() async -> LibrarySyncCoordinator.SyncResult {
        updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .running
            status.pendingConflictSummary = nil
            status.currentPhase = nil
            status.lastFailureReason = nil
            status.degradedReason = nil
            status.lastResult = nil
        }
        guard cloudSyncStateController.hasRequiredBootstrapInputs() else {
            recordLibraryCloudSyncFailure(
                trigger: .firstEnableBootstrap,
                phase: nil,
                result: .permanentFailure,
                reason: "A TMDb API key is required before iCloud library sync can be enabled.",
                degradedReason: "iCloud library sync enablement is blocked until a TMDb API key is configured."
            )
            updateLibraryCloudSyncStatus { status in
                status.bootstrapState = .failed
            }
            return .permanentFailure
        }
        guard let syncCoordinator else {
            recordLibraryCloudSyncFailure(
                trigger: .firstEnableBootstrap,
                phase: nil,
                result: .permanentFailure,
                reason: "The iCloud library sync coordinator was unavailable.",
                degradedReason: "iCloud library sync enablement is blocked because the sync coordinator is unavailable."
            )
            updateLibraryCloudSyncStatus { status in
                status.bootstrapState = .failed
            }
            return .permanentFailure
        }
        return await syncCoordinator.bootstrapFirstEnablement(preference: nil)
    }

    @discardableResult
    func resolveLibraryCloudSyncConflicts(preference: LibraryCloudSyncConflictPreference) async -> Bool {
        guard cloudSyncStateController.canResolveFirstEnablementConflict(libraryCloudSyncStatus) else {
            return false
        }
        guard let syncCoordinator else { return false }
        return await syncCoordinator.bootstrapFirstEnablement(preference: preference).succeeded
    }

    func cancelLibraryCloudSyncEnablement() {
        guard cloudSyncStateController.canCancelFirstEnablement(libraryCloudSyncStatus) else {
            return
        }
        cancelOrdinaryLibrarySyncTasks()
        syncCoordinator?.cancelOrdinarySync()
        syncCoordinator?.cancelFirstEnableBootstrap()
        resetLibraryCloudSyncDisabledState(resetRetryState: false)
    }

    func disableLibraryCloudSync() {
        cancelOrdinaryLibrarySyncTasks()
        syncCoordinator?.cancelOrdinarySync()
        syncCoordinator?.cancelFirstEnableBootstrap()
        resetLibraryCloudSyncDisabledState(resetRetryState: true)
    }

    func resetLibraryCloudSyncAfterBackupRestore() {
        cancelOrdinaryLibrarySyncTasks()
        syncCoordinator?.cancelOrdinarySync()
        syncCoordinator?.cancelFirstEnableBootstrap()
        syncScheduler?.resetRetryBackoff()
        updateLibraryCloudSyncStatus { status in
            status = .defaultValue
        }
    }

    func resetLibraryCloudSyncChangeTokens() {
        guard let syncCoordinator else {
            CloudLibrarySyncChangeTokenStore().removeAllTokens()
            return
        }
        syncCoordinator.removeAllChangeTokens()
    }

    private func resetLibraryCloudSyncDisabledState(resetRetryState: Bool) {
        if resetRetryState {
            syncScheduler?.resetRetryBackoff()
        }
        updateLibraryCloudSyncStatus { status in
            status.isEnabled = false
            status.bootstrapState = .notStarted
            status.pendingConflictSummary = nil
            status.currentPhase = nil
            status.lastResult = .skipped
            status.lastFailureReason = nil
            status.degradedReason = nil
            if resetRetryState {
                status.retryState = .idle
            }
        }
    }

    private func cancelOrdinaryLibrarySyncTasks() {
        for syncTask in ordinarySyncTasks.values {
            syncTask.cancel()
        }
        ordinarySyncTasks.removeAll()
    }

    @discardableResult
    func retryLibraryCloudSync() async -> Bool {
        if libraryCloudSyncStatus.isEnabled,
            libraryCloudSyncStatus.bootstrapState == .failed
                || libraryCloudSyncStatus.bootstrapState == .notStarted
        {
            return await enableLibraryCloudSync()
        }
        return await performLibrarySync(trigger: .manualRetry)
    }

    func libraryCloudSyncPolicyBlockReason() -> LibraryCloudSyncPolicyBlockReason? {
        cloudSyncStateController.policyBlockReason(for: libraryCloudSyncStatus)
    }

    func updateLibraryCloudSyncStatus(_ update: (inout LibraryCloudSyncStatus) -> Void) {
        libraryCloudSyncStatus = cloudSyncStateController.persist(
            libraryCloudSyncStatus,
            updating: update
        )
    }

    func recordLibraryCloudSyncPhase(
        trigger: LibrarySyncCoordinator.Trigger,
        phase: LibraryCloudSyncPhase,
        at date: Date = .now
    ) {
        updateLibraryCloudSyncStatus { status in
            status.currentPhase = phase
            status.lastResult = nil
            status.lastTrigger = trigger.rawValue
            status.lastAttemptDate = date
            status.lastFailureReason = nil
            status.degradedReason = nil
        }
    }

    func recordLibraryCloudSyncSkipped(
        trigger: LibrarySyncCoordinator.Trigger,
        reason: LibraryCloudSyncPolicyBlockReason,
        at date: Date = .now
    ) {
        updateLibraryCloudSyncStatus { status in
            status.currentPhase = nil
            status.lastResult = .skipped
            status.lastTrigger = trigger.rawValue
            status.lastAttemptDate = date
            status.lastFailureReason = reason.rawValue
        }
    }

    func recordLibraryCloudSyncSuccess(
        trigger: LibrarySyncCoordinator.Trigger,
        completedBootstrap: Bool,
        at date: Date = .now
    ) {
        updateLibraryCloudSyncStatus { status in
            if completedBootstrap {
                status.bootstrapState = .completed
            }
            status.currentPhase = nil
            status.lastResult = .success
            status.lastTrigger = trigger.rawValue
            status.lastAttemptDate = date
            status.lastSuccessfulSyncDate = date
            status.lastFailureReason = nil
            status.degradedReason = nil
            status.pendingConflictSummary = nil
        }
    }

    func recordLibraryCloudSyncFailure(
        trigger: LibrarySyncCoordinator.Trigger,
        phase _: LibraryCloudSyncPhase?,
        result: LibraryCloudSyncResultClass,
        reason: String,
        degradedReason: String? = nil,
        at date: Date = .now
    ) {
        updateLibraryCloudSyncStatus { status in
            status.currentPhase = nil
            status.lastResult = result
            status.lastTrigger = trigger.rawValue
            status.lastAttemptDate = date
            status.lastFailureReason = reason
            if let degradedReason {
                status.degradedReason = degradedReason
            }
        }
    }

    func recordLibraryCloudSyncConflictNeeded(
        summary: LibraryCloudSyncConflictSummary,
        at date: Date = .now
    ) {
        updateLibraryCloudSyncStatus { status in
            status.bootstrapState = .needsConflictChoice
            status.pendingConflictSummary = summary
            status.currentPhase = nil
            status.lastResult = .conflictChoiceRequired
            status.lastTrigger = LibrarySyncCoordinator.Trigger.firstEnableBootstrap.rawValue
            status.lastAttemptDate = date
            status.lastFailureReason = nil
        }
    }

    func updateLibraryCloudKitAvailability(_ availability: LibraryCloudKitAvailability) {
        updateLibraryCloudSyncStatus { status in
            status.cloudKitAvailability = availability
        }
    }

    func updateLibraryCloudSyncRetryState(_ retryState: LibraryCloudSyncRetryState) {
        updateLibraryCloudSyncStatus { status in
            status.retryState = retryState
        }
    }

    func markLibraryCloudSyncDegraded(_ reason: String) {
        updateLibraryCloudSyncStatus { status in
            status.degradedReason = reason
        }
    }

    func configureLibrarySyncCoordinator(
        client: CloudLibrarySyncClient? = nil,
        database: CloudLibrarySyncDatabase? = nil,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init(),
        namespaceProvider: (@MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?)? = nil,
        hydrateMissingEntry: @escaping @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry =
            LibrarySyncCoordinator.hydrateMissingEntry,
        dateProvider: @escaping @MainActor @Sendable () -> Date = { .now }
    ) {
        syncCoordinator = LibrarySyncCoordinator(
            store: self,
            client: client,
            database: database,
            changeTokenStore: changeTokenStore,
            namespaceProvider: namespaceProvider,
            hydrateMissingEntry: hydrateMissingEntry,
            dateProvider: dateProvider
        )
    }

    private func setupLibrarySyncScheduling() {
        guard !dataProvider.inMemory else { return }
        let scheduler = LibrarySyncScheduler(
            hasPendingDirtyWork: { [weak syncChangeRecorder] in
                guard let syncChangeRecorder else { return false }
                return !syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty
            },
            sync: { [weak self] trigger in
                guard let self else { return .permanentFailure }
                guard let syncCoordinator else { return .permanentFailure }
                return await syncCoordinator.syncResult(trigger: trigger)
            },
            retryStateDidChange: { [weak self] retryState in
                self?.updateLibraryCloudSyncRetryState(retryState)
            },
            degradedStateDidChange: { [weak self] reason in
                self?.markLibraryCloudSyncDegraded(reason)
            }
        )
        syncScheduler = scheduler
        syncChangeRecorder.onDirtyQueueChanged = { [weak scheduler] in
            scheduler?.scheduleLocalDirtyQueueSync()
        }
    }

    func setupTMDbAPIConfigurationChangeMonitor() {
        NotificationCenter.default
            .publisher(for: .tmdbAPIConfigurationDidChange)
            .sink { [weak self] _ in
                self?.infoFetcher = .init()
            }
            .store(in: &cancellables)
    }

    private func setupCloudSyncedPreferencesMonitor() {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: preferences.notificationObject)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCloudSyncedPreferenceChange()
            }
            .store(in: &cancellables)
    }

    private func handleCloudSyncedPreferenceChange() {
        let currentHash = preferences.cloudSyncedSettingsPayloadHash()
        guard currentHash != lastObservedCloudSyncedPreferencesHash else { return }
        lastObservedCloudSyncedPreferencesHash = currentHash
        if isApplyingRemoteCloudSyncedPreferences {
            reloadPersistedPreferences()
            return
        }

        preferences.saveCloudSyncedDefaultsUpdatedAt(.now)
        reloadPersistedPreferences()
        guard libraryCloudSyncStatus.isEnabled else { return }
        syncLibrary(trigger: .localDirtyQueueChange)
    }

    // MARK: - Shared Helpers

    func existingEntry(tmdbID: Int) -> AnimeEntry? {
        repository.existingEntry(tmdbID: tmdbID)
    }

    func applyNewEntryDefaults(to entry: AnimeEntry) {
        let now = Date.now
        entry.updateWatchStatus(defaultNewEntryWatchStatus, at: now)
        entry.markCreatedForLibrary(at: now)
    }

    func applyDefaultFilters() {
        filters = defaultFilters
    }
}

#if DEBUG
    extension LibraryStore {
        /// Mock delete, doesn't really touch anything in the persisted data model.
        ///
        /// Restores after 1.5 seconds.
        func mockDeleteEntry(_ entry: AnimeEntry) {
            if let index = library.firstIndex(where: { $0.id == entry.id }) {
                library.remove(at: index)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.library.insert(entry, at: index)
                }
            }
        }
    }
#endif
