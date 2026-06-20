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
    @ObservationIgnored private var saveObserver: ModelContextSaveObserver?
    @ObservationIgnored private var deferredLibraryRefreshDepth = 0
    @ObservationIgnored private var needsDeferredLibraryRefresh = false
    private(set) var libraryRevision = 0

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
    var longTermGalleryPosterCachingEnabled: Bool = false {
        willSet {
            preferences.saveLongTermGalleryPosterCachingEnabled(newValue)
            libraryStoreLogger.debug("Updated long-term gallery poster caching to \(newValue)")
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
        if longTermGalleryPosterCachingEnabled != snapshot.longTermGalleryPosterCachingEnabled {
            longTermGalleryPosterCachingEnabled = snapshot.longTermGalleryPosterCachingEnabled
        }
        if libraryCloudSyncStatus != snapshot.cloudSyncStatus {
            libraryCloudSyncStatus = snapshot.cloudSyncStatus
        }

        applyDefaultFilters()
    }

    func applyRemoteCloudSyncedPreferences(_ snapshot: LibrarySettingsSyncSnapshot) {
        libraryStoreLogger.info(
            "Applying iCloud settings snapshot updated at \(snapshot.updatedAt, privacy: .public) with \(snapshot.payload.count, privacy: .public) keys."
        )
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
            libraryRevision &+= 1
        }
    }

    func setupUpdateLibrary() {
        saveObserver = ModelContextSaveObserver { [weak self] _ in
            self?.handleLibrarySaveNotification()
        }
    }

    private func handleLibrarySaveNotification() {
        if deferredLibraryRefreshDepth > 0 {
            needsDeferredLibraryRefresh = true
            return
        }

        do {
            try refreshLibrary()
        } catch {
            libraryStoreLogger.error("Error refreshing library: \(error)")
        }
    }

    func performWithDeferredLibrarySaveRefresh<T>(_ operation: () async throws -> T) async rethrows -> T {
        deferredLibraryRefreshDepth += 1
        do {
            let result = try await operation()
            await drainQueuedMainThreadSaveNotifications()
            finishDeferredLibrarySaveRefresh()
            return result
        } catch {
            await drainQueuedMainThreadSaveNotifications()
            finishDeferredLibrarySaveRefresh()
            throw error
        }
    }

    private func finishDeferredLibrarySaveRefresh() {
        guard deferredLibraryRefreshDepth > 0 else { return }
        deferredLibraryRefreshDepth -= 1
        guard deferredLibraryRefreshDepth == 0, needsDeferredLibraryRefresh else { return }

        needsDeferredLibraryRefresh = false
        do {
            try refreshLibrary()
        } catch {
            libraryStoreLogger.error("Error refreshing library after deferred saves: \(error)")
        }
    }

    private func drainQueuedMainThreadSaveNotifications() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    func rebuildSyncChangeTracking() {
        syncChangeRecorder.rebuildBaseline()
    }

    /// Runs an async write scope without treating its SwiftData saves as local sync edits.
    ///
    /// Callers can wrap arbitrary async store mutations here, including work that saves through
    /// detached model actors rather than only the main-context `repository.save()`. After the
    /// operation completes, the sync recorder baseline is rebuilt from the resulting store state.
    func performWithoutSyncRecording<T>(_ operation: () async throws -> T) async throws -> T {
        let result = try await syncChangeRecorder.withSuppressedRecording {
            try await operation()
        }
        rebuildSyncChangeTracking()
        return result
    }

    func syncLibrary(trigger: LibrarySyncCoordinator.Trigger) {
        Task {
            await performLibrarySyncResult(trigger: trigger)
        }
    }

    func flushPendingLocalLibrarySync() {
        syncScheduler?.flushPendingLocalSync()
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
        if result == .success {
            resetOrdinaryLibrarySyncRetryBackoff()
        }
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

    /// Resets persisted sync metadata that belonged to a replaced local store.
    ///
    /// Store replacement invalidates any queued local CloudKit mutations and any
    /// previously committed server tokens because both refer to rows that no
    /// longer exist in the fresh store. If sync was enabled, the next sync must
    /// resume through first-enable bootstrap so CloudKit can repopulate the
    /// replacement store from scratch.
    func prepareLibraryCloudSyncAfterPersistentStoreRecovery() {
        cancelOrdinaryLibrarySyncTasks()
        syncCoordinator?.cancelOrdinarySync()
        syncCoordinator?.cancelFirstEnableBootstrap()
        syncScheduler?.resetRetryBackoff()

        do {
            try syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        } catch {
            libraryStoreLogger.error(
                "Failed to clear persisted iCloud sync dirty work after startup store recovery: \(error.localizedDescription, privacy: .private)"
            )
        }
        resetLibraryCloudSyncChangeTokens()
        rebuildSyncChangeTracking()

        guard libraryCloudSyncStatus.isEnabled else {
            shouldResumeInterruptedCloudSyncBootstrap = false
            return
        }

        shouldResumeInterruptedCloudSyncBootstrap = true
        updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .running
            status.pendingConflictSummary = nil
            status.retryState = .idle
            status.currentPhase = nil
            status.lastResult = nil
            status.lastFailureReason = nil
            status.degradedReason = nil
        }
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
        reconciledCloudSyncedSettingsUpdatedAt: Date?,
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
            status.lastReconciledCloudSyncedSettingsUpdatedAt =
                reconciledCloudSyncedSettingsUpdatedAt
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

    private func resetOrdinaryLibrarySyncRetryBackoff() {
        if let syncScheduler {
            syncScheduler.resetRetryBackoff()
            return
        }
        updateLibraryCloudSyncStatus { status in
            status.retryState = .idle
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
            hasPendingLocalWork: { [weak self] in
                self?.hasPendingLocalLibrarySyncWork() ?? false
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
            scheduler?.schedulePendingLocalSync()
        }
    }

    func hasPendingLocalLibrarySyncWork() -> Bool {
        hasPendingLibraryEntrySyncWork() || hasPendingCloudSyncedSettingsSyncWork()
    }

    private func hasPendingLibraryEntrySyncWork() -> Bool {
        !syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty
    }

    func hasPendingCloudSyncedSettingsSyncWork() -> Bool {
        guard let updatedAt = preferences.cloudSyncedDefaultsUpdatedAt() else { return false }
        let payload = preferences.loadCloudSyncedSettingsSnapshot(fallbackUpdatedAt: updatedAt).payload
        guard !payload.isEmpty else { return false }
        guard
            let lastReconciledUpdatedAt =
                libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
        else {
            return true
        }
        return updatedAt > lastReconciledUpdatedAt
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
            libraryStoreLogger.debug(
                "Observed iCloud settings change while applying remote snapshot; refreshed preferences without restamping the local clock."
            )
            reloadPersistedPreferences()
            return
        }

        let updatedAt = Date.now
        preferences.saveCloudSyncedDefaultsUpdatedAt(updatedAt)
        libraryStoreLogger.info(
            "Detected local cloud-synced settings change and updated the local settings clock to \(updatedAt, privacy: .public)."
        )
        reloadPersistedPreferences()
        guard libraryCloudSyncStatus.isEnabled else { return }
        libraryStoreLogger.debug("Scheduled iCloud settings sync for local preference changes.")
        schedulePendingLocalLibrarySync()
    }

    private func schedulePendingLocalLibrarySync() {
        guard let syncScheduler else {
            syncLibrary(trigger: .localChange)
            return
        }
        syncScheduler.schedulePendingLocalSync()
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
