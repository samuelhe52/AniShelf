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
import UIKit

@main
struct MyAnimeListApp: App {
    @UIApplicationDelegateAdaptor(LibrarySyncNotificationBridge.self) private var notificationBridge
    @State var libraryStore: LibraryStore
    @State var keyStorage: TMDbAPIKeyStorage
    @State var whatsNew: WhatsNewController
    @State var supportStore: SupportStore
    @State private var appReview: AppReviewPromptController
    @State private var startupRecovery: PersistentStoreRecovery?
    @State private var backgroundSyncExecution: LibrarySyncBackgroundExecutionController
    private let recoveryActivityGate: StartupRecoveryActivityGate
    private let lifecycleEventGate = AppLifecycleEventGate()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(.preferredAnimeInfoLanguage) var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    init() {
        let startupBootstrap = DataProvider.startupBootstrap
        let startupRecovery = Self.startupRecovery(
            bootstrapRecovery: startupBootstrap.recovery
        )
        let keyStorage = TMDbAPIKeyStorage()
        let recoveryActivityGate = StartupRecoveryActivityGate(
            isBlocked: startupRecovery != nil
        )
        let libraryStore = LibraryStore(
            dataProvider: startupBootstrap.provider,
            hasTMDbAPIKey: {
                guard let key = keyStorage.key else { return false }
                return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            airingReminderPruningEnabled: recoveryActivityGate.allowsLibraryActivity
        )
        let whatsNew = WhatsNewController()
        let supportStore = SupportStore()
        let appReview = AppReviewPromptController()

        _libraryStore = State(initialValue: libraryStore)
        _keyStorage = State(initialValue: keyStorage)
        _whatsNew = State(initialValue: whatsNew)
        _supportStore = State(initialValue: supportStore)
        _appReview = State(initialValue: appReview)
        _startupRecovery = State(initialValue: startupRecovery)
        _backgroundSyncExecution = State(
            initialValue: LibrarySyncBackgroundExecutionController()
        )
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
    }

    private static func startupRecovery(
        bootstrapRecovery: PersistentStoreRecovery?
    ) -> PersistentStoreRecovery? {
        bootstrapRecovery
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let startupRecovery {
                    StartupRecoveryView(
                        recovery: startupRecovery,
                        onContinue: continueAfterStartupRecovery
                    )
                } else if let key = keyStorage.key, !key.isEmpty {
                    LibraryView()
                        .onAppear {
                            libraryStore.language = followsSystemLanguage ? .current : preferredLanguage
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                } else if keyStorage.lookupState == .checking {
                    ProgressView(checkingTMDbAPIKeyResource)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    TMDbAPIOnboardingView()
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                }
            }
            .environment(libraryStore)
            .environment(keyStorage)
            .environment(whatsNew)
            .environment(supportStore)
            .environment(appReview)
            .onAppear {
                guard lifecycleEventGate.shouldHandleLaunch() else { return }
                keyStorage.retryInitialLookupIfNeeded()
                if startupRecovery == nil {
                    requestSync(trigger: .appLaunch)
                    recordActiveLibraryDayIfUsable()
                    refreshAiringReminders()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // scenePhase here is the app-level phase; every window delivers each transition.
                guard lifecycleEventGate.shouldHandlePhaseChange(to: newPhase) else { return }
                if newPhase == .active {
                    keyStorage.retryInitialLookupIfNeeded()
                    requestSync(trigger: .foreground)
                    recordActiveLibraryDayIfUsable()
                    refreshAiringReminders()
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
            .providesWindowSceneIdentifier()
        }
    }

    private func updateWhatsNewPresentation() {
        guard startupRecovery == nil else { return }
        whatsNew.presentIfNeeded(allowsAutoPresentation: hasTMDbAPIKey)
    }

    private func continueAfterStartupRecovery() {
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
        guard startupRecovery == nil else { return }
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

    private var hasTMDbAPIKey: Bool {
        guard let key = keyStorage.key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recordActiveLibraryDayIfUsable() {
        guard scenePhase == .active, startupRecovery == nil, hasTMDbAPIKey else { return }
        guard !libraryStore.requiresDuplicateRepair else { return }
        appReview.recordActiveLibraryDay()
    }

    private func refreshAiringReminders() {
        Task { @MainActor in
            await AiringReminderCoordinator.shared.reloadState()
            _ = await AiringReminderCoordinator.shared.refreshAll()
        }
    }

    private var checkingTMDbAPIKeyResource: LocalizedStringResource {
        "Checking TMDb API key..."
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
        WhatsNewView(
            entry: entry,
            pastEntries: pastEntries,
            actionRunner: actionRunner,
            onDismiss: onDismiss
        )
    }
}
