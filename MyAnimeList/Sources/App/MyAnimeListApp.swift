//
//  MyAnimeListApp.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import StoreKit
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@main
struct MyAnimeListApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(LibrarySyncNotificationBridge.self) private var notificationBridge
    #else
        @UIApplicationDelegateAdaptor(LibrarySyncNotificationBridge.self) private var notificationBridge
    #endif
    @State var libraryStore: LibraryStore
    @State var keyStorage: TMDbAPIKeyStorage
    @State var whatsNew: WhatsNewController
    @State var supportStore: SupportStore
    @State private var appReview: AppReviewPromptController
    @State private var startupRecovery: PersistentStoreRecovery?
    /// Set when the store was saved by a newer schema; the app stays blocked for this launch.
    private let newerLibraryStoreVersion: Schema.Version?
    /// A DEBUG launch argument replaced the real store; library and sync work stay off for this launch.
    private let isSimulatedStartup: Bool
    /// A DEBUG or `LIBRARY_FIXTURES` launch argument replaced the store with a generated library;
    /// sync, reminders, and prompts stay off for this launch (docs-ai 026).
    private let isLibraryFixture: Bool
    @State private var backgroundSyncExecution: LibrarySyncBackgroundExecutionController
    private let recoveryActivityGate: StartupRecoveryActivityGate
    private let lifecycleEventGate = AppLifecycleEventGate()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(.preferredAnimeInfoLanguage) var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    init() {
        let startup = Self.startupEnvironment()
        let startupBootstrap = startup.bootstrap
        let isSimulatedStartup = startup.isSimulated
        let startupRecovery = startupBootstrap.recovery
        let newerLibraryStoreVersion: Schema.Version? =
            if case .requiresNewerApp(let storeVersion) = startupBootstrap.status {
                storeVersion
            } else {
                nil
            }
        let keyStorage = TMDbAPIKeyStorage()
        #if DEBUG
            AIDebugLaunch.start(
                configuration: AIConfiguration(defaults: startup.defaults), isFixture: startup.isLibraryFixture
            )
        #endif
        // A newer-store block never lifts: only an app update can open the library.
        // A fixture library stays blocked too, so sync and reminders never act on it.
        let recoveryActivityGate = StartupRecoveryActivityGate(
            isBlocked: startupRecovery != nil || newerLibraryStoreVersion != nil || startup.isLibraryFixture
        )
        let libraryStore = LibraryStore(
            dataProvider: startupBootstrap.provider,
            preferences: LibraryPreferences(defaults: startup.defaults),
            hasTMDbAPIKey: {
                guard let key = keyStorage.key else { return false }
                return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            airingReminderPruningEnabled: recoveryActivityGate.allowsLibraryActivity,
            allowsCloudSync: !startup.isLibraryFixture
        )
        let whatsNew = WhatsNewController(defaults: startup.defaults)
        let supportStore = SupportStore()
        let appReview = AppReviewPromptController(defaults: startup.defaults)
        self.isLibraryFixture = startup.isLibraryFixture

        _libraryStore = State(initialValue: libraryStore)
        _keyStorage = State(initialValue: keyStorage)
        _whatsNew = State(initialValue: whatsNew)
        _supportStore = State(initialValue: supportStore)
        _appReview = State(initialValue: appReview)
        _startupRecovery = State(initialValue: startupRecovery)
        self.newerLibraryStoreVersion = newerLibraryStoreVersion
        self.isSimulatedStartup = isSimulatedStartup
        let backgroundSyncExecution = LibrarySyncBackgroundExecutionController()
        _backgroundSyncExecution = State(initialValue: backgroundSyncExecution)
        self.recoveryActivityGate = recoveryActivityGate
        RecoveryExportManager.cleanupAllTemporaryExports()

        LibrarySyncNotificationBridge.configureSyncHandler { [libraryStore, recoveryActivityGate] in
            guard recoveryActivityGate.allowsLibraryActivity else { return .noData }
            guard !libraryStore.requiresDuplicateRepair else { return .noData }
            let result = await libraryStore.performLibrarySyncResult(trigger: .cloudNotification)
            switch result {
            case .success:
                return .newData
            case .skipped(_):
                return .noData
            case .conflictChoiceRequired, .retryableFailure, .permanentFailure:
                return .failed
            }
        }
        #if os(macOS)
            Self.configureMacLifecycle(
                libraryStore: libraryStore,
                keyStorage: keyStorage,
                appReview: appReview,
                recoveryActivityGate: recoveryActivityGate,
                lifecycleEventGate: lifecycleEventGate,
                backgroundSyncExecution: backgroundSyncExecution
            )
        #endif
    }

    #if os(macOS)
        /// Wires app-lifetime events into the shared objects directly: the App value captured
        /// here would hold stale `@State` once startup recovery finishes.
        private static func configureMacLifecycle(
            libraryStore: LibraryStore,
            keyStorage: TMDbAPIKeyStorage,
            appReview: AppReviewPromptController,
            recoveryActivityGate: StartupRecoveryActivityGate,
            lifecycleEventGate: AppLifecycleEventGate,
            backgroundSyncExecution: LibrarySyncBackgroundExecutionController
        ) {
            let canSyncLibrary = { @MainActor in
                recoveryActivityGate.allowsLibraryActivity && !libraryStore.requiresDuplicateRepair
            }
            // The Mac's foreground work; iOS runs it from the app-level scene phase instead,
            // which needs a window and so misses activations while every window is closed.
            LibrarySyncNotificationBridge.configureActivation {
                // Launch handling already syncs and refreshes for the first activation, but it
                // can run before the app is active, so every activation records the active day.
                let isLaunchActivation = !lifecycleEventGate.shouldHandleActivation()
                if !isLaunchActivation { keyStorage.retryInitialLookupIfNeeded() }
                guard recoveryActivityGate.allowsLibraryActivity, keyStorage.hasUsableKey else { return }
                if !libraryStore.requiresDuplicateRepair {
                    appReview.recordActiveLibraryDay()
                    if !isLaunchActivation { libraryStore.syncLibrary(trigger: .foreground) }
                }
                guard !isLaunchActivation else { return }
                Task { @MainActor in
                    await AiringReminderCoordinator.shared.reloadState()
                    _ = await AiringReminderCoordinator.shared.refreshAll()
                }
            }
            LibrarySyncNotificationBridge.configureSleepAndWake(
                willSleep: {
                    guard canSyncLibrary(), libraryStore.needsBackgroundLibrarySyncProtection else { return }
                    backgroundSyncExecution.run(
                        onExpiration: { libraryStore.cancelLibrarySyncForBackgroundExpiration() },
                        operation: { _ = await libraryStore.flushPendingLocalLibrarySyncAndWait() }
                    )
                },
                didWake: {
                    guard canSyncLibrary() else { return }
                    libraryStore.syncLibrary(trigger: .foreground)
                }
            )
        }
    #endif

    private struct StartupEnvironment {
        var bootstrap: DataProviderBootstrapResult
        var isSimulated = false
        var isLibraryFixture = false
        var defaults: UserDefaults = .standard
    }

    private static func startupEnvironment() -> StartupEnvironment {
        #if DEBUG
            // Preview startup screens without opening or touching the real store.
            let arguments = ProcessInfo.processInfo.arguments
            // Shows the half-star score hint again, for visual checks.
            if arguments.contains("-reset-score-hint") {
                UserDefaults.standard.removeObject(forKey: .entryScoreHalfHintSeen)
            }
            if arguments.contains("-simulate-newer-library-store") {
                return StartupEnvironment(
                    bootstrap: DataProvider.newerStorePlaceholderBootstrap(
                        storeVersion: Schema.Version(99, 0, 0)
                    ),
                    isSimulated: true
                )
            }
            if arguments.contains("-simulate-startup-recovery") {
                return StartupEnvironment(bootstrap: DataProvider.simulatedRecoveryBootstrap(), isSimulated: true)
            }
        #endif
        #if DEBUG || LIBRARY_FIXTURES
            // A generated library for scale checks and the UI benchmarks; never opens the real store.
            if let fixture = LibraryFixture.fromLaunchArguments() {
                return StartupEnvironment(
                    bootstrap: fixture.makeBootstrap(),
                    isLibraryFixture: true,
                    defaults: fixture.defaults
                )
            }
        #endif
        return StartupEnvironment(bootstrap: DataProvider.startupBootstrap)
    }

    var body: some Scene {
        #if os(macOS)
            WindowGroup(id: MacWindowID.library) {
                libraryWindowContent
            }
            .defaultSize(width: 1180, height: 760)
            .commands {
                SidebarCommands()
                MacLibraryCommands(whatsNew: whatsNew)
            }

            Window("About AniShelf", id: MacWindowID.about) {
                MacAboutView()
            }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .defaultPosition(.center)
            .restorationBehavior(.disabled)
            .commandsRemoved()

            Window("Support AniShelf", id: MacWindowID.support) {
                MacSupportView()
                    .environment(supportStore)
                    .globalToasts()
                    .providesWindowSceneIdentifier(role: .auxiliary)
            }
            .windowResizability(.contentSize)
            .defaultPosition(.center)
            .restorationBehavior(.disabled)
            .commandsRemoved()

            Settings {
                MacSettingsRoot(isLibraryBlocked: isLibraryBlocked || !hasTMDbAPIKey)
                    .environment(libraryStore)
                    .environment(keyStorage)
                    .environment(whatsNew)
                    .environment(supportStore)
                    .environment(appReview)
                    // What's New opened from Settings presents in the Settings window.
                    .modifier(WhatsNewPresenter(whatsNew: whatsNew, libraryStore: libraryStore))
                    .globalToasts()
                    .providesWindowSceneIdentifier(role: .auxiliary)
            }
        #else
            WindowGroup {
                libraryWindowContent
            }
        #endif
    }

    @ViewBuilder
    private var libraryRoot: some View {
        #if os(macOS)
            MacLibraryView()
        #else
            LibraryView()
        #endif
    }

    private var libraryWindowContent: some View {
        ZStack {
            if let newerLibraryStoreVersion {
                NewerLibraryStoreView(storeVersion: newerLibraryStoreVersion)
            } else if let startupRecovery {
                StartupRecoveryView(
                    recovery: startupRecovery,
                    onContinue: continueAfterStartupRecovery
                )
            } else if let key = keyStorage.key, !key.isEmpty {
                libraryRoot
                    .libraryBrowseScope()
                    .onAppear {
                        libraryStore.language = followsSystemLanguage ? .current : preferredLanguage
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else if keyStorage.lookupState == .checking {
                ProgressView(checkingTMDbAPIKeyResource)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                TMDbAPIOnboardingView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        #if (DEBUG || LIBRARY_FIXTURES) && os(iOS)
            .overlay(alignment: .topLeading) {
                if isLibraryFixture {
                    LibraryFrameStatsElement()
                    .frame(width: 1, height: 1)
                }
            }
        #endif
        .environment(libraryStore)
        .environment(keyStorage)
        .environment(whatsNew)
        .environment(supportStore)
        .environment(appReview)
        .onAppear {
            guard lifecycleEventGate.shouldHandleLaunch() else { return }
            keyStorage.retryInitialLookupIfNeeded()
            if !isLibraryBlocked {
                requestSync(trigger: .appLaunch)
                recordActiveLibraryDayIfUsable()
                refreshAiringReminders()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // scenePhase here is the app-level phase; every window delivers each transition.
            guard lifecycleEventGate.shouldHandlePhaseChange(to: newPhase) else { return }
            if newPhase == .active {
                // The Mac handles activation in its app delegate (`configureMacLifecycle`).
                #if !os(macOS)
                    keyStorage.retryInitialLookupIfNeeded()
                    requestSync(trigger: .foreground)
                    recordActiveLibraryDayIfUsable()
                    refreshAiringReminders()
                #endif
            } else if newPhase == .background {
                flushPendingLocalSync()
            }
        }
        .modifier(WhatsNewPresenter(whatsNew: whatsNew, libraryStore: libraryStore))
        .onAppear(perform: updateWhatsNewPresentation)
        .onChange(of: keyStorage.key) { _, newKey in
            guard lifecycleEventGate.shouldHandleKeyChange(to: newKey) else { return }
            updateWhatsNewPresentation()
            recordActiveLibraryDayIfUsable()
            if hasTMDbAPIKey {
                requestSync(trigger: .foreground)
            }
        }
        .modifier(AppReviewPromptPresenter(appReview: appReview))
        .globalToasts()
        .providesWindowSceneIdentifier(role: .library)
    }

    private func updateWhatsNewPresentation() {
        guard !isLibraryBlocked, !isLibraryFixture else { return }
        whatsNew.presentIfNeeded(allowsAutoPresentation: hasTMDbAPIKey)
    }

    private func continueAfterStartupRecovery() {
        if isSimulatedStartup {
            // Skip the sync reset and reminder pruning: both act on real preferences and iCloud.
            if let startupRecovery {
                DataProvider.acknowledgePersistentStoreRecovery(startupRecovery)
            }
            startupRecovery = nil
            return
        }
        libraryStore.prepareLibraryCloudSyncAfterPersistentStoreRecovery()
        if let startupRecovery {
            DataProvider.acknowledgePersistentStoreRecovery(startupRecovery)
        }
        recoveryActivityGate.isBlocked = false
        startupRecovery = nil
        libraryStore.enableAiringReminderPruning()
        requestSync(trigger: .appLaunch)
        updateWhatsNewPresentation()
    }

    private func requestSync(trigger: LibrarySyncCoordinator.Trigger) {
        guard !isLibraryBlocked, !isLibraryFixture else { return }
        guard !libraryStore.requiresDuplicateRepair else { return }
        libraryStore.syncLibrary(trigger: trigger)
    }

    private func flushPendingLocalSync() {
        guard recoveryActivityGate.allowsLibraryActivity else { return }
        guard !libraryStore.requiresDuplicateRepair else { return }
        guard libraryStore.needsBackgroundLibrarySyncProtection else { return }
        backgroundSyncExecution.run(
            onExpiration: {
                libraryStore.cancelLibrarySyncForBackgroundExpiration()
            },
            operation: {
                _ = await libraryStore.flushPendingLocalLibrarySyncAndWait()
            }
        )
    }

    private var isLibraryBlocked: Bool {
        startupRecovery != nil || newerLibraryStoreVersion != nil || isSimulatedStartup
    }

    private var hasTMDbAPIKey: Bool {
        keyStorage.hasUsableKey
    }

    private func recordActiveLibraryDayIfUsable() {
        guard scenePhase == .active, !isLibraryBlocked, !isLibraryFixture, hasTMDbAPIKey else { return }
        guard !libraryStore.requiresDuplicateRepair else { return }
        appReview.recordActiveLibraryDay()
    }

    private func refreshAiringReminders() {
        guard !isLibraryFixture else { return }
        Task { @MainActor in
            await AiringReminderCoordinator.shared.reloadState()
            _ = await AiringReminderCoordinator.shared.refreshAll()
        }
    }

    private var checkingTMDbAPIKeyResource: LocalizedStringResource {
        "Checking TMDb API key…"
    }
}

@MainActor
final class StartupRecoveryActivityGate {
    var isBlocked: Bool

    var allowsLibraryActivity: Bool {
        !isBlocked
    }

    init(isBlocked: Bool) {
        self.isBlocked = isBlocked
    }
}

/// Shows What's New only in the window that claimed it; other windows' bindings stay `nil`.
fileprivate struct WhatsNewPresenter: ViewModifier {
    let whatsNew: WhatsNewController
    let libraryStore: LibraryStore
    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier

    func body(content: Content) -> some View {
        content
            .onChange(of: whatsNew.presentedEntry?.version, initial: true) { claimIfNeeded() }
            .onChange(of: windowSceneIdentifier) { claimIfNeeded() }
            // A claim held by a closed window passes to the first open window that asks.
            .onChange(of: AppWindowCoordinator.shared.registeredWindowIDs) { _, openWindows in
                whatsNew.releasePresentation(ifNotIn: openWindows)
                claimIfNeeded()
            }
            .sheet(item: presentedEntry) { entry in
                NavigationStack {
                    WhatsNewRootSheet(
                        entry: entry,
                        pastEntries: whatsNew.presentationSource == .settings
                            ? WhatsNewRegistry.pastEntries(before: entry.version)
                            : [],
                        settingsActions: .init(store: libraryStore),
                        onDismiss: { whatsNew.dismissPresentedEntry() }
                    )
                }
                .presentationDetents([.large])
                .presentationSizing(.page)
            }
    }

    private var presentedEntry: Binding<WhatsNewEntry?> {
        Binding(
            get: { whatsNew.presentedEntry(forSceneIdentifier: windowSceneIdentifier) },
            set: { newValue in
                if newValue == nil {
                    whatsNew.dismissPresentedEntry()
                }
            }
        )
    }

    private func claimIfNeeded() {
        whatsNew.claimPresentation(forSceneIdentifier: windowSceneIdentifier)
    }
}

/// Requests reviews from a window's own environment so StoreKit presents in that window.
fileprivate struct AppReviewPromptPresenter: ViewModifier {
    let appReview: AppReviewPromptController
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: taskID) {
                guard appReview.scheduledRequestToken != nil, scenePhase == .active else { return }
                try? await Task.sleep(for: .seconds(2))
                // prepareForRequest consumes the token, so only one active window requests.
                guard !Task.isCancelled, scenePhase == .active, appReview.prepareForRequest() else {
                    return
                }
                requestReview()
            }
    }

    private var taskID: String {
        "\(appReview.scheduledRequestToken?.uuidString ?? "none")-\(scenePhase)"
    }
}

fileprivate struct WhatsNewRootSheet: View {
    let entry: WhatsNewEntry
    let pastEntries: [WhatsNewEntry]
    let onDismiss: () -> Void

    @State private var actionRunner: WhatsNewActionRunner

    init(
        entry: WhatsNewEntry,
        pastEntries: [WhatsNewEntry],
        settingsActions: LibraryProfileSettingsActions,
        onDismiss: @escaping () -> Void
    ) {
        self.entry = entry
        self.pastEntries = pastEntries
        self.onDismiss = onDismiss
        _actionRunner = State(initialValue: settingsActions.makeWhatsNewActionRunner())
    }

    var body: some View {
        #if os(macOS)
            MacWhatsNewView(
                entry: entry,
                pastEntries: pastEntries,
                actionRunner: actionRunner,
                onDismiss: onDismiss
            )
        #else
            WhatsNewView(
                entry: entry,
                pastEntries: pastEntries,
                actionRunner: actionRunner,
                onDismiss: onDismiss
            )
        #endif
    }
}
