//
//  MyAnimeListApp.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
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
    @State private var startupRecovery: PersistentStoreRecovery?
    private let recoveryActivityGate: StartupRecoveryActivityGate
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
        let libraryStore = LibraryStore(
            dataProvider: startupBootstrap.provider,
            hasTMDbAPIKey: {
                guard let key = keyStorage.key else { return false }
                return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        let whatsNew = WhatsNewController()
        let supportStore = SupportStore()
        let recoveryActivityGate = StartupRecoveryActivityGate(
            isBlocked: startupRecovery != nil
        )

        _libraryStore = State(initialValue: libraryStore)
        _keyStorage = State(initialValue: keyStorage)
        _whatsNew = State(initialValue: whatsNew)
        _supportStore = State(initialValue: supportStore)
        _startupRecovery = State(initialValue: startupRecovery)
        self.recoveryActivityGate = recoveryActivityGate
        RecoveryExportManager.cleanupAllTemporaryExports()

        LibrarySyncNotificationBridge.configureSyncHandler { [libraryStore, recoveryActivityGate] in
            guard recoveryActivityGate.allowsLibraryActivity else { return .noData }
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
                } else {
                    TMDbAPIOnboardingView()
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                }
            }
            .environment(libraryStore)
            .environment(keyStorage)
            .environment(whatsNew)
            .environment(supportStore)
            .environment(\.dataHandler, DataProvider.default.dataHandler)
            .onAppear {
                if startupRecovery == nil {
                    requestSync(trigger: .appLaunch)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    requestSync(trigger: .foreground)
                } else if newPhase == .background {
                    flushPendingLocalSync()
                }
            }
            .sheet(item: presentedWhatsNewEntry) { entry in
                NavigationStack {
                    WhatsNewRootSheet(
                        entry: entry,
                        settingsActions: .init(store: libraryStore),
                        onDismiss: { whatsNew.dismissPresentedEntry() }
                    )
                }
                .presentationDetents([.large])
            }
            .onAppear(perform: updateWhatsNewPresentation)
            .onChange(of: keyStorage.key) { _, _ in
                updateWhatsNewPresentation()
            }
            .globalToasts()
        }
    }

    private var presentedWhatsNewEntry: Binding<WhatsNewEntry?> {
        Binding(
            get: { whatsNew.presentedEntry },
            set: { newValue in
                if let newValue {
                    whatsNew.presentedEntry = newValue
                } else {
                    whatsNew.dismissPresentedEntry()
                }
            }
        )
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
        requestSync(trigger: .appLaunch)
        updateWhatsNewPresentation()
    }

    private func requestSync(trigger: LibrarySyncCoordinator.Trigger) {
        guard startupRecovery == nil else { return }
        libraryStore.syncLibrary(trigger: trigger)
    }

    private func flushPendingLocalSync() {
        guard recoveryActivityGate.allowsLibraryActivity else { return }
        libraryStore.flushPendingLocalLibrarySync()
    }

    private var hasTMDbAPIKey: Bool {
        guard let key = keyStorage.key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

fileprivate struct WhatsNewRootSheet: View {
    let entry: WhatsNewEntry
    let onDismiss: () -> Void

    @State private var actionRunner: WhatsNewActionRunner

    init(
        entry: WhatsNewEntry,
        settingsActions: LibraryProfileSettingsActions,
        onDismiss: @escaping () -> Void
    ) {
        self.entry = entry
        self.onDismiss = onDismiss
        _actionRunner = State(initialValue: settingsActions.makeWhatsNewActionRunner())
    }

    var body: some View {
        WhatsNewView(
            entry: entry,
            actionRunner: actionRunner,
            onDismiss: onDismiss
        )
    }
}
